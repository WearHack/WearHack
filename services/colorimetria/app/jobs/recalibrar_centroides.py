"""Recalibracion de los centroides de estacion con las correcciones de los usuarios (#37).

Los centroides de cada estacion se corrigen con lo que los usuarios confirman.
Sin esto, un sesgo del modelo inicial se queda fijo para siempre.

    docker compose --profile jobs run --rm \\
        -v <carpeta del conjunto>:/evaluacion:ro \\
        -e RUTA_CONJUNTO_EVALUACION=/evaluacion/conjunto.json \\
        jobs-colorimetria python -m app.jobs.recalibrar_centroides [--tope 0.5]

Reglas (respuestas B.11):

- Mezcla por eje: nuevo = (n0 * actual + suma de correcciones) / (n0 + n), n0 = 25.
  Se trabaja en el espacio estandarizado del clasificador, el mismo de los centroides.
- Solo entran las estaciones con al menos 20 correcciones nuevas; las demas esperan.
- Tope de movimiento por eje (`--tope`, en desviaciones estandar).
- Solo se mueven los ejes medidos. Hoy la correccion (`correcciones_colorimetria`,
  del Core) guarda solo el Lab de la piel, asi que solo se mueven las variables de
  piel que salen de el (L, a, b, C, h, calidez, a/L, b/L). Cabello, ojos, contraste,
  S y V no se mueven.
- Sin retroceso: la version nueva se evalua contra un conjunto fijo (JSON, ver
  `leer_conjunto`). Si la exactitud de la estacion o de una capa empeora mas de un
  punto, se descarta. Sin conjunto tambien se descarta: no se publica nada sin medir.
- Versionado y reversible: se publica una version nueva con
  `RepositorioCentroides` y se activa. Para volver atras:
  `python -m app.jobs.publicar_centroides activar <version anterior>`.
- Cada corrida que publica deja en `recalibraciones` hasta que correccion consumio
  (`correcciones_hasta`), que es lo que lee la desvinculacion del Core. Una corrida
  descartada deja su registro sin esa marca: sus correcciones no se consumieron.

La recalibracion del color de prenda no es este job: es una tarea del Core.
"""

import argparse
import copy
import json
import logging
import math
import os
from collections import defaultdict
from collections.abc import Iterable, Mapping
from datetime import UTC, datetime
from pathlib import Path

import numpy as np

from app.centroides import COLECCION as COLECCION_CENTROIDES
from app.centroides import RepositorioCentroides
from app.clasificador import CAPAS, ESTACIONES, ClasificadorJerarquico
from app.config import ajustes
from app.jobs._runner import ResultadoJob, salir

log = logging.getLogger(__name__)

COLECCION_CORRECCIONES = "correcciones_colorimetria"
COLECCION_RECALIBRACIONES = "recalibraciones"

N0 = 25
MIN_CORRECCIONES_POR_ESTACION = 20
TOPE_POR_EJE = 0.5
MAX_RETROCESO = 0.01  # un punto de exactitud

# Por debajo, a/L y b/L se disparan con el ruido (igual que en app/extraccion/variables.py).
_L_MINIMA_PARA_RAZONES = 5.0


def estacion_de(temporada: str | None) -> str | None:
    """La estacion de 4 a partir de lo que guarde el Core (`OTONO`, `otono_suave`, `Otoño`)."""
    if not temporada:
        return None
    base = temporada.strip().upper().replace("Ñ", "N").split("_")[0].split(" ")[0]
    return base if base in ESTACIONES else None


def variables_de_piel(lab: Mapping | None) -> dict[str, float]:
    """Las variables del clasificador que salen solo del Lab de la piel."""
    if not lab:
        return {}
    try:
        luz, a, b = float(lab["l"]), float(lab["a"]), float(lab["b"])
    except (KeyError, TypeError, ValueError):
        return {}
    variables = {
        "piel_L": luz,
        "piel_a": a,
        "piel_b": b,
        "piel_C": math.hypot(a, b),
        "piel_h": math.degrees(math.atan2(b, a)) % 360,
        "piel_calidez": b - a,
    }
    if luz >= _L_MINIMA_PARA_RAZONES:
        variables["piel_a_L"] = a / luz
        variables["piel_b_L"] = b / luz
    return variables


def correcciones_nuevas(coleccion, marca: datetime | None) -> list[dict]:
    """Las vinculadas posteriores a la ultima marca. Las desvinculadas ya no cuentan."""
    nuevas = []
    for c in coleccion.find({"creada_en": {"$exists": True}}):
        creada = _utc(c.get("creada_en"))
        if creada is not None and (marca is None or creada > marca):
            nuevas.append({**c, "creada_en": creada})
    return nuevas


def ultima_marca(coleccion) -> datetime | None:
    marcas = [_utc(r.get("correcciones_hasta")) for r in coleccion.find({})]
    marcas = [m for m in marcas if m is not None]
    return max(marcas) if marcas else None


def _utc(valor) -> datetime | None:
    if not isinstance(valor, datetime):
        return None
    return valor if valor.tzinfo else valor.replace(tzinfo=UTC)


def agrupar(correcciones: Iterable[dict]) -> dict[str, list[dict[str, float]]]:
    """Variables medidas por estacion confirmada. Las que no se entienden se saltan."""
    por_estacion: dict[str, list[dict[str, float]]] = defaultdict(list)
    for c in correcciones:
        estacion = estacion_de(c.get("temporada_confirmada"))
        variables = variables_de_piel(c.get("piel"))
        if estacion and variables:
            por_estacion[estacion].append(variables)
    return dict(por_estacion)


def mezclar(
    datos: dict,
    por_estacion: Mapping[str, list[dict[str, float]]],
    n0: int = N0,
    tope: float = TOPE_POR_EJE,
) -> tuple[dict, dict[str, list[str]]]:
    """Centroides nuevos en una copia del artefacto. Devuelve tambien los ejes movidos.

    Cada estacion aporta a una clase por capa (por ejemplo, OTONO a CALIDO en subtono
    y a ALTO en contraste). Por eje, solo cuentan las correcciones que lo midieron.
    """
    nuevo = copy.deepcopy(datos)
    estandarizacion = nuevo["estandarizacion"]
    movidos: dict[str, list[str]] = defaultdict(list)
    for indice_capa, nombre_capa in enumerate(CAPAS):
        capa = nuevo["capas"][nombre_capa]
        for clase, centroide in capa["centroides"].items():
            muestras = [
                m
                for estacion, ms in por_estacion.items()
                if ESTACIONES[estacion][indice_capa] == clase
                for m in ms
            ]
            for j, variable in enumerate(capa["variables"]):
                valores = [m[variable] for m in muestras if variable in m]
                if not valores:
                    continue
                media = estandarizacion["media"][variable]
                desviacion = estandarizacion["desviacion"][variable]
                z = (np.array(valores) - media) / desviacion
                actual = centroide[j]
                mezcla = (n0 * actual + z.sum()) / (n0 + len(z))
                centroide[j] = float(actual + np.clip(mezcla - actual, -tope, tope))
                movidos[f"{nombre_capa}.{clase}"].append(variable)
    return nuevo, dict(movidos)


def leer_conjunto(ruta: Path) -> list[dict]:
    """Conjunto fijo de evaluacion: lista JSON de `{"variables": {...}, "estacion": "OTONO"}`.

    Sale de la particion de prueba de `calibracion/` y no va en la imagen ni en el
    repositorio (Deep Armocromia, solo MVP academico).
    """
    filas = json.loads(Path(ruta).read_text(encoding="utf-8"))
    return [f for f in filas if f.get("estacion") in ESTACIONES and f.get("variables")]


def exactitudes(clasificador: ClasificadorJerarquico, conjunto: list[dict]) -> dict[str, float]:
    """Exactitud de la estacion y de cada capa sobre el conjunto fijo."""
    aciertos = {"estacion": 0, **{c: 0 for c in CAPAS}}
    for fila in conjunto:
        resultado = clasificador.clasificar(fila["variables"])
        if resultado is None:
            continue
        esperada = fila["estacion"]
        aciertos["estacion"] += resultado.estacion == esperada
        for indice, capa in enumerate(CAPAS):
            elegida = max(resultado.capas[capa], key=resultado.capas[capa].get)
            aciertos[capa] += elegida == ESTACIONES[esperada][indice]
    total = len(conjunto) or 1
    return {k: v / total for k, v in aciertos.items()}


def empeora(antes: Mapping[str, float], despues: Mapping[str, float]) -> list[str]:
    return [k for k in antes if despues[k] < antes[k] - MAX_RETROCESO]


def version_recalibrada(vigente: str, ahora: datetime) -> str:
    """`4-estaciones-v1+r202610300300`. El sufijo no se acumula entre corridas."""
    return f"{vigente.split('+r')[0]}+r{ahora:%Y%m%d%H%M}"


def recalibrar_en(
    base,
    conjunto: list[dict] | None,
    tope: float = TOPE_POR_EJE,
    ahora: datetime | None = None,
) -> ResultadoJob:
    """La corrida completa sobre una base de pymongo (o algo que se le parezca)."""
    ahora = ahora or datetime.now(UTC)
    repositorio = RepositorioCentroides(base[COLECCION_CENTROIDES])
    recalibraciones = base[COLECCION_RECALIBRACIONES]

    nuevas = correcciones_nuevas(base[COLECCION_CORRECCIONES], ultima_marca(recalibraciones))
    por_estacion = agrupar(nuevas)
    conteo = {e: len(ms) for e, ms in sorted(por_estacion.items())}
    listas = {e: ms for e, ms in por_estacion.items() if len(ms) >= MIN_CORRECCIONES_POR_ESTACION}
    if not listas:
        log.info(
            "Ninguna estacion llega a %d correcciones nuevas: %s",
            MIN_CORRECCIONES_POR_ESTACION,
            conteo,
        )
        return ResultadoJob(umbral_alcanzado=False)

    vigente = repositorio.version_vigente()
    datos = repositorio.cargar(vigente) if vigente else None
    if datos is None:
        log.warning("No hay centroides vigentes que recalibrar")
        return ResultadoJob(umbral_alcanzado=True)

    nuevo, movidos = mezclar(datos, listas, tope=tope)
    nuevo["version"] = version_recalibrada(vigente, ahora)
    estaciones = sorted(listas)
    consumidas = [c for c in nuevas if estacion_de(c.get("temporada_confirmada")) in listas]
    registro = {
        "ejecutada_en": ahora,
        "version_base": vigente,
        "correcciones_por_estacion": {e: len(listas[e]) for e in estaciones},
        "ejes_movidos": movidos,
        "n0": N0,
        "tope": tope,
    }

    motivo = None
    if not movidos:
        motivo = "ningun eje medido coincide con las variables del clasificador"
    elif not conjunto:
        motivo = "sin conjunto de evaluacion: no se publica nada sin medir"
    else:
        antes = exactitudes(ClasificadorJerarquico.desde_dict(datos), conjunto)
        despues = exactitudes(ClasificadorJerarquico.desde_dict(nuevo), conjunto)
        registro["metricas"] = {"antes": antes, "despues": despues}
        peores = empeora(antes, despues)
        if peores:
            motivo = f"empeora mas de un punto en {', '.join(peores)}"

    if motivo:
        log.warning("Recalibracion descartada: %s", motivo)
        recalibraciones.insert_one({**registro, "estado": "descartada", "motivo": motivo})
        return ResultadoJob(umbral_alcanzado=True)

    nuevo["recalibracion"] = {
        "desde": vigente,
        "correcciones": registro["correcciones_por_estacion"],
    }
    version = repositorio.publicar(nuevo)
    repositorio.activar(version)
    recalibraciones.insert_one(
        {
            **registro,
            "estado": "publicada",
            "version_nueva": version,
            "correcciones_hasta": max(c["creada_en"] for c in consumidas),
        }
    )
    usuarios = {c.get("usuario_id") for c in consumidas if c.get("usuario_id")}
    log.info("Centroides %s publicados y activos (antes %s)", version, vigente)
    return ResultadoJob(umbral_alcanzado=True, usuarios_afectados=len(usuarios))


def argumentos(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--tope",
        type=float,
        default=TOPE_POR_EJE,
        help="Movimiento maximo por eje (desv. estandar)",
    )
    parser.add_argument(
        "--conjunto",
        type=Path,
        default=os.environ.get("RUTA_CONJUNTO_EVALUACION"),
        help="JSON del conjunto fijo de evaluacion (o RUTA_CONJUNTO_EVALUACION)",
    )
    return parser.parse_args(argv)


def recalibrar(argv: list[str] | None = None) -> ResultadoJob:
    from pymongo import MongoClient

    args = argumentos(argv)
    conjunto = leer_conjunto(args.conjunto) if args.conjunto else None
    cliente = MongoClient(ajustes().mongo_uri, serverSelectionTimeoutMS=5000)
    try:
        return recalibrar_en(cliente.get_default_database("wearhack"), conjunto, args.tope)
    finally:
        cliente.close()


if __name__ == "__main__":
    salir("recalibrar_centroides", recalibrar)
