"""Ranking nocturno de prendas puente por usuario (#38).

Una prenda puente es una del catalogo de marcas aliadas que desbloquea varios
outfits nuevos combinada con lo que el usuario ya tiene. Es lo que monetiza el
producto, y se precalcula de noche porque recorrer el catalogo entero contra
cada closet es caro para hacerlo en linea.

    docker compose --profile jobs run --rm jobs-recomendador \\
        python -m app.jobs.ranking_prendas_puente

La logica es la del motor (`app/motor/puente.py`), la misma que en tiempo real:
este job solo lee, traduce y escribe.

Lee (solo lectura, usuario `wh_jobs`):
- `prendas`: el closet de cada usuario.
- `catalogos_marcas`: las candidatas. Mismo esquema que `prendas` (`slot_outfit`
  y `atributos`), sin `usuario_id`. En el init local la coleccion se llama
  `catalogos`; aqui se usa el nombre de `infra/datos/README.md`, que es el que
  tiene permisos en Atlas.
- `configuracion`: `outfits` (los dress codes, que son los eventos) y
  `recomendacion` (pesos iniciales, reglas y `prenda_puente.umbral_combinaciones_buenas`).
- `pesos_usuario`: los pesos personales, si los hay.

Escribe solo en `ranking_prenda_puente`, un documento por usuario (`_id` = sub de
Cognito), que Publicidad lee en solo lectura:

    {_id, puentes: [{prenda_id, combinaciones_buenas, eventos_nuevos, costo_medio}],
     umbral, calculado_en}

Sin perfil de colorimetria (es del Core y el usuario de los jobs no lo lee), la
paleta no cuenta: w_paleta = 0, igual que en el motor en linea sin perfil. Los
"outfits actuales" con los que se compara cada candidata son los que el motor le
recomendaria hoy al usuario sin contexto (sin clima ni evento).
"""

import logging
from collections.abc import Iterable, Mapping
from datetime import UTC, datetime
from math import inf

from pydantic import ValidationError

from app.api.v1.recomendador import Candidato
from app.config import ajustes
from app.jobs._runner import ResultadoJob, salir
from app.motor.modelos import Formalidad, Prenda, RangoFormalidad
from app.motor.motor import Contexto, funcion_costo, pesos_para, recomendar
from app.motor.puente import UMBRAL_COMBINACIONES, EvaluacionPuente, ReglasPuente, rankear_puentes
from app.pesos import RepositorioPesosMongo

log = logging.getLogger(__name__)

COLECCION_PRENDAS = "prendas"
COLECCION_CATALOGO = "catalogos_marcas"
COLECCION_CONFIGURACION = "configuracion"
COLECCION_PESOS = "pesos_usuario"
COLECCION_RANKING = "ranking_prenda_puente"

# Cuantas puentes se guardan por usuario. Publicidad muestra unas pocas; el resto
# solo ocuparia espacio en el tier Free de Atlas.
MAX_PUENTES = 20


def prenda_desde_documento(documento: Mapping) -> Prenda:
    """Un documento de `prendas` o del catalogo, traducido al modelo del motor.

    Reusa la validacion del endpoint (`Candidato`): los dos hablan el mismo esquema,
    solo que en Mongo los atributos van anidados.

    El esquema es el de Atlas (`infra/datos/wearhack-mongo-setup.js`, #41). Tambien
    acepta el del init local (`infra/local/mongo/init/`), mas viejo: `color` en la
    raiz, `lab` como `{l, a, b}` y la formalidad como un solo nivel.
    """
    atributos = documento.get("atributos") or {}
    color = atributos.get("color") or documento.get("color") or {}
    lab = color.get("lab")
    if isinstance(lab, Mapping):
        lab = [lab.get("l"), lab.get("a"), lab.get("b")]
    formalidad = atributos.get("formalidad")
    if isinstance(formalidad, str):
        formalidad = {"min": formalidad, "max": formalidad}
    return Candidato(
        id=str(documento["_id"]),
        slot_outfit=documento.get("slot_outfit"),
        lab=lab,
        tipo=atributos.get("tipo") or documento.get("tipo"),
        textura=atributos.get("textura"),
        patron=atributos.get("patron") or "LISO",
        formalidad=formalidad,
        clima_apto=atributos.get("clima_apto") or [],
        version_esquema=documento.get("version_esquema", 1),
    ).a_motor()


def prendas_validas(documentos: Iterable[Mapping], origen: str) -> list[Prenda]:
    """Las que se pueden traducir. Las demas se saltan y se avisa solo con el id."""
    prendas = []
    for documento in documentos:
        try:
            prendas.append(prenda_desde_documento(documento))
        except (KeyError, TypeError, ValidationError):
            log.warning("Documento de %s invalido, se salta: %s", origen, documento.get("_id"))
    return prendas


def eventos_desde(documento_outfits: Mapping | None) -> dict[str, RangoFormalidad]:
    """Los dress codes de `configuracion.outfits` como eventos del motor."""
    eventos = {}
    for nombre, rango in ((documento_outfits or {}).get("dress_codes") or {}).items():
        try:
            eventos[nombre] = (Formalidad[rango["min"]], Formalidad[rango["max"]])
        except (KeyError, TypeError):
            log.warning("Dress code %s invalido, se salta", nombre)
    return eventos


def reglas_puente_desde(documento_recomendacion: Mapping | None) -> ReglasPuente:
    umbral = ((documento_recomendacion or {}).get("prenda_puente") or {}).get(
        "umbral_combinaciones_buenas"
    )
    if isinstance(umbral, int) and not isinstance(umbral, bool) and umbral >= 1:
        return ReglasPuente(umbral=umbral)
    return ReglasPuente(umbral=UMBRAL_COMBINACIONES)


def ranking_de_usuario(
    usuario_id: str,
    closet: list[Prenda],
    catalogo: list[Prenda],
    repositorio: RepositorioPesosMongo,
    eventos: Mapping[str, RangoFormalidad],
    reglas_puente: ReglasPuente,
) -> list[EvaluacionPuente]:
    configuracion = repositorio.configuracion()
    contexto = Contexto()
    pesos = pesos_para(usuario_id, repositorio, contexto.perfil)
    costo = funcion_costo(contexto, pesos, configuracion.reglas)
    actuales = [o.prendas for o in recomendar(closet, contexto, pesos, configuracion.reglas)]
    puentes = rankear_puentes(catalogo, closet, actuales, costo, eventos, reglas=reglas_puente)
    return puentes[:MAX_PUENTES]


def documento_ranking(
    usuario_id: str, puentes: list[EvaluacionPuente], umbral: int, ahora: datetime
) -> dict:
    return {
        "_id": usuario_id,
        "puentes": [
            {
                "prenda_id": p.candidata.id,
                "combinaciones_buenas": p.combinaciones_buenas,
                "eventos_nuevos": p.eventos_nuevos,
                # Una puente tiene al menos `umbral` combinaciones: el costo es finito.
                "costo_medio": round(p.costo_medio, 6) if p.costo_medio != inf else None,
            }
            for p in puentes
        ],
        "umbral": umbral,
        "calculado_en": ahora,
    }


def rankear_todos(base, ahora: datetime | None = None) -> ResultadoJob:
    """Recalcula el ranking de cada usuario con closet. `base` es una base de pymongo."""
    ahora = ahora or datetime.now(UTC)
    configuracion = base[COLECCION_CONFIGURACION]
    eventos = eventos_desde(configuracion.find_one({"_id": "outfits"}))
    reglas_puente = reglas_puente_desde(configuracion.find_one({"_id": "recomendacion"}))
    repositorio = RepositorioPesosMongo(configuracion, base[COLECCION_PESOS], intervalo=inf)

    catalogo = prendas_validas(base[COLECCION_CATALOGO].find({}), "catalogo")
    if not catalogo:
        log.info("Catalogo vacio: no hay prendas puente que calcular")

    ranking = base[COLECCION_RANKING]
    usuarios = con_puentes = 0
    for usuario_id in base[COLECCION_PRENDAS].distinct("usuario_id"):
        closet = prendas_validas(
            base[COLECCION_PRENDAS].find({"usuario_id": usuario_id}), "prendas"
        )
        puentes = (
            ranking_de_usuario(usuario_id, closet, catalogo, repositorio, eventos, reglas_puente)
            if catalogo
            else []
        )
        # Se reemplaza siempre: un ranking viejo no debe sobrevivir a un catalogo nuevo.
        ranking.replace_one(
            {"_id": usuario_id},
            documento_ranking(usuario_id, puentes, reglas_puente.umbral, ahora),
            upsert=True,
        )
        usuarios += 1
        con_puentes += bool(puentes)

    log.info("Ranking recalculado: %d usuarios, %d con prendas puente", usuarios, con_puentes)
    return ResultadoJob(umbral_alcanzado=con_puentes > 0, usuarios_afectados=con_puentes)


def rankear() -> ResultadoJob:
    from pymongo import MongoClient

    cliente = MongoClient(ajustes().mongo_uri, serverSelectionTimeoutMS=5000)
    try:
        return rankear_todos(cliente.get_default_database("wearhack"))
    finally:
        cliente.close()


if __name__ == "__main__":
    salir("ranking_prendas_puente", rankear)
