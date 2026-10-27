"""Paso 2: elige variables y muestreo, calcula los centroides y mide RNF07 (E.29).

    python -m calibracion.calibrar

Todo lo que se elige (variante de muestreo, variables de cada capa) se elige
con validacion cruzada estratificada de 5 pliegues **solo sobre train**. El
conjunto de prueba se usa una vez, al final, para medir.

Escribe en la carpeta de salida:
- `centroides-4-estaciones-v1.json`: el artefacto que carga el servicio.
- `metricas.json` y `informe.md`.
"""

import argparse
import csv
import itertools
import json
import math
import sys
from dataclasses import asdict
from datetime import UTC, datetime

import numpy as np

from app.clasificador import CAPAS, ESTACIONES, Capa, ClasificadorJerarquico
from app.extraccion.muestreo import CANALES, Muestra
from app.extraccion.segmentacion import ParametrosSegmentacion
from app.extraccion.variables import calcular_variables
from calibracion import configuracion
from calibracion.extraer import PERTURBACIONES, VARIANTES

VERSION = "4-estaciones-v1"
SEMILLA = 42
PLIEGUES = 5
MAX_VARIABLES = 10
MEJORA_MINIMA = 0.002
BOOTSTRAP = 1000

# Pixeles minimos por region tras el recorte (A.8: no definido). Provisionales,
# sobre recortes de 768 px de lado como maximo.
MINIMOS = {"piel": 500, "cabello": 300, "ojos": 30}

NOMBRES = list(calcular_variables({}).keys())

# Bandas de ITA (Chardon et al., 1991; Del Bino et al., 2006). Proxy de la
# escala Monk: Deep Armocromia no trae anotacion Monk.
BANDAS_ITA = [
    ("muy_clara", 55, math.inf),
    ("clara", 41, 55),
    ("intermedia", 28, 41),
    ("bronceada", 10, 28),
    ("morena", -30, 10),
    ("oscura", -math.inf, -30),
]


# --------------------------------------------------------------------------- #
# Datos
# --------------------------------------------------------------------------- #


def leer(ruta) -> list[dict]:
    with open(ruta, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def _muestra(fila: dict, region: str, variante: str) -> Muestra | None:
    prefijo = f"{region}__{variante}__"
    n = int(fila.get(prefijo + "n") or 0)
    if fila["fallo"] or n < MINIMOS[region]:
        return None
    return Muestra(**{c: float(fila[prefijo + c]) for c in CANALES}, pixeles=n)


def matriz(filas: list[dict], muestreo: tuple[str, str]) -> np.ndarray:
    """(n, variables). `muestreo` = (variante de piel y cabello, variante de ojos)."""
    principal, ojos = muestreo
    salida = np.full((len(filas), len(NOMBRES)), np.nan)
    for i, fila in enumerate(filas):
        if fila["fallo"]:
            continue
        v = calcular_variables(
            {
                "piel": _muestra(fila, "piel", principal),
                "cabello": _muestra(fila, "cabello", principal),
                "ojos": _muestra(fila, "ojos", ojos),
            }
        )
        salida[i] = [v[n] for n in NOMBRES]
    return salida


def etiquetas(filas: list[dict]) -> dict[str, np.ndarray]:
    estacion = np.array([f["estacion"] for f in filas])
    return {
        "estacion": estacion,
        "subtono": np.array([ESTACIONES[e][0] for e in estacion]),
        "contraste": np.array([ESTACIONES[e][1] for e in estacion]),
    }


def pliegues(y: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    """Pliegue de cada fila, estratificado por clase."""
    asignacion = np.empty(len(y), int)
    for clase in np.unique(y):
        indices = rng.permutation(np.flatnonzero(y == clase))
        asignacion[indices] = np.arange(len(indices)) % PLIEGUES
    return asignacion


# --------------------------------------------------------------------------- #
# Centroide mas cercano, vectorizado para la busqueda
# --------------------------------------------------------------------------- #


def _estandarizacion(x: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    media = np.nanmean(x, axis=0)
    desviacion = np.nanstd(x, axis=0)
    return media, np.where(desviacion > 0, desviacion, 1.0)


def _centroides(z: np.ndarray, y: np.ndarray, clases: list[str]) -> np.ndarray:
    return np.stack([np.nanmean(z[y == c], axis=0) for c in clases])


def _distancias(z: np.ndarray, c: np.ndarray) -> np.ndarray:
    dif = z[:, None, :] - c[None, :, :]
    d = np.sqrt(np.nansum(dif**2, axis=2))
    return np.where((~np.isnan(dif)).any(axis=2), d, np.inf)


def _predecir(z_train, y_train, z_val, clases) -> np.ndarray:
    """Indice de clase predicha; -1 si la fila no tiene ningun eje."""
    d = _distancias(z_val, _centroides(z_train, y_train, clases))
    return np.where(np.isfinite(d).any(axis=1), d.argmin(axis=1), -1)


class Validacion:
    """Pliegues ya estandarizados: la busqueda voraz solo indexa columnas."""

    def __init__(self, x: np.ndarray, asignacion: np.ndarray) -> None:
        self.partes = []
        for k in range(PLIEGUES):
            entrena, valida = asignacion != k, asignacion == k
            media, desviacion = _estandarizacion(x[entrena])
            z = (x - media) / desviacion
            self.partes.append((entrena, valida, z[entrena], z[valida]))

    def _indices(self, y: np.ndarray, columnas: list[int]) -> tuple[list[str], np.ndarray]:
        clases = sorted(np.unique(y))
        pred = np.full(len(y), -1)
        for entrena, valida, z_entrena, z_valida in self.partes:
            pred[valida] = _predecir(
                z_entrena[:, columnas], y[entrena], z_valida[:, columnas], clases
            )
        return clases, pred

    def predicciones(self, y: np.ndarray, columnas: list[int]) -> np.ndarray:
        clases, pred = self._indices(y, columnas)
        return np.array([clases[j] if j >= 0 else None for j in pred], dtype=object)

    def exactitud(self, y: np.ndarray, columnas: list[int]) -> float:
        clases, pred = self._indices(y, columnas)
        reales = np.searchsorted(clases, y)
        return float(np.mean(pred == reales))


def seleccion_voraz(val: Validacion, y: np.ndarray) -> tuple[list[int], list[float]]:
    elegidas: list[int] = []
    historial: list[float] = []
    mejor = 0.0
    while len(elegidas) < MAX_VARIABLES:
        candidatas = [c for c in range(len(NOMBRES)) if c not in elegidas]
        puntuaciones = [val.exactitud(y, elegidas + [c]) for c in candidatas]
        k = int(np.argmax(puntuaciones))
        if puntuaciones[k] - mejor < MEJORA_MINIMA:
            break
        elegidas.append(candidatas[k])
        historial.append(puntuaciones[k])
        mejor = puntuaciones[k]
    return elegidas, historial


def combinar(subtono: np.ndarray, contraste: np.ndarray) -> np.ndarray:
    inversa = {v: k for k, v in ESTACIONES.items()}
    return np.array(
        [inversa.get((s, c)) if s and c else None for s, c in zip(subtono, contraste)]
    )


# --------------------------------------------------------------------------- #
# Metricas
# --------------------------------------------------------------------------- #


def intervalo(aciertos: np.ndarray, rng: np.random.Generator) -> list[float]:
    medias = [rng.choice(aciertos, len(aciertos)).mean() for _ in range(BOOTSTRAP)]
    return [float(np.percentile(medias, 2.5)), float(np.percentile(medias, 97.5))]


def ita(x: np.ndarray) -> np.ndarray:
    L, b = x[:, NOMBRES.index("piel_L")], x[:, NOMBRES.index("piel_b")]
    return np.degrees(np.arctan((L - 50) / b))


def banda_ita(valor: float) -> str:
    if math.isnan(valor):
        return "sin_piel"
    return next(n for n, bajo, alto in BANDAS_ITA if bajo <= valor < alto)


def predecir_test(modelo: ClasificadorJerarquico, x: np.ndarray):
    por_capa = modelo.probabilidades_por_capa(x, NOMBRES)
    estaciones, p = modelo.probabilidades_por_estacion(por_capa)
    valido = ~np.isnan(p).any(axis=1)
    orden = np.argsort(-np.nan_to_num(p, nan=-1), axis=1)
    primera = np.where(valido, np.array(estaciones)[orden[:, 0]], None)
    segunda = np.where(valido, np.array(estaciones)[orden[:, 1]], None)
    capas = {
        n: np.where(valido, np.array(modelo.capas[n].clases)[np.nanargmax(np.nan_to_num(
            por_capa[n], nan=-1), axis=1)], None)
        for n in CAPAS
    }
    return primera, segunda, capas, valido


def exactitudes(y: dict, primera, segunda, capas, rng) -> dict:
    aciertos = {
        "estacion": primera == y["estacion"],
        "subtono": capas["subtono"] == y["subtono"],
        "contraste": capas["contraste"] == y["contraste"],
        "top2": (primera == y["estacion"]) | (segunda == y["estacion"]),
    }
    return {
        k: {"exactitud": float(v.mean()), "ic95": intervalo(v.astype(float), rng), "n": len(v)}
        for k, v in aciertos.items()
    }


# --------------------------------------------------------------------------- #


def principal(argv: list[str] | None = None) -> int:
    argparse.ArgumentParser(description=__doc__.splitlines()[0]).parse_args(argv)
    rutas = configuracion.cargar()
    rng = np.random.default_rng(SEMILLA)

    filas = leer(rutas.salida / "regiones.csv")
    train = [f for f in filas if f["particion"] == "train"]
    test = [f for f in filas if f["particion"] == "test"]
    y_train, y_test = etiquetas(train), etiquetas(test)
    asignacion = pliegues(y_train["estacion"], rng)

    # 1. Variante de muestreo y variables de cada capa, por validacion cruzada.
    candidatos = []
    for principal_, ojos in itertools.product(VARIANTES["piel"], VARIANTES["ojos"]):
        muestreo = (principal_.nombre, ojos.nombre)
        x = matriz(train, muestreo)
        val = Validacion(x, asignacion)
        seleccion = {capa: seleccion_voraz(val, y_train[capa]) for capa in CAPAS}
        pred = {capa: val.predicciones(y_train[capa], seleccion[capa][0]) for capa in CAPAS}
        exactitud = float(np.mean(combinar(pred["subtono"], pred["contraste"]) == y_train["estacion"]))
        plano = seleccion_voraz(val, y_train["estacion"])
        candidatos.append(
            {
                "muestreo": muestreo,
                "cv_estacion": exactitud,
                "cv_capas": {c: seleccion[c][1][-1] if seleccion[c][1] else 0.0 for c in CAPAS},
                "cv_plano": plano[1][-1] if plano[1] else 0.0,
                "variables": {c: [NOMBRES[i] for i in seleccion[c][0]] for c in CAPAS},
                "variables_plano": [NOMBRES[i] for i in plano[0]],
            }
        )
        print(f"{muestreo}: CV estacion {exactitud:.3f}  plano {candidatos[-1]['cv_plano']:.3f}")
    elegido = max(candidatos, key=lambda c: c["cv_estacion"])

    # 2. Centroides finales con todo train.
    x_train = matriz(train, elegido["muestreo"])
    usadas = sorted({v for c in CAPAS for v in elegido["variables"][c]} | set(elegido["variables_plano"]))
    media, desviacion = _estandarizacion(x_train)
    media_d = {n: float(media[NOMBRES.index(n)]) for n in usadas}
    desv_d = {n: float(desviacion[NOMBRES.index(n)]) for n in usadas}
    z_train = (x_train - media) / desviacion

    def capa(nombre_y: str, variables: list[str]) -> Capa:
        clases = sorted(np.unique(y_train[nombre_y]))
        cols = [NOMBRES.index(v) for v in variables]
        return Capa(variables, clases, _centroides(z_train[:, cols], y_train[nombre_y], clases))

    modelo = ClasificadorJerarquico(
        {c: capa(c, elegido["variables"][c]) for c in CAPAS}, media_d, desv_d, VERSION
    )

    # 3. Evaluacion en test: una sola vez.
    x_test = matriz(test, elegido["muestreo"])
    primera, segunda, capas, valido = predecir_test(modelo, x_test)
    metricas = {"cobertura": float(valido.mean()), **exactitudes(y_test, primera, segunda, capas, rng)}

    estaciones = list(ESTACIONES)
    metricas["confusion"] = {
        real: {pred: int(np.sum((y_test["estacion"] == real) & (primera == pred))) for pred in estaciones}
        for real in estaciones
    }

    # Linea base plana (4 centroides) con el mismo muestreo, para comparar.
    plano = capa("estacion", elegido["variables_plano"])
    cols = [NOMBRES.index(v) for v in plano.variables]
    z_test = (x_test - media) / desviacion
    i = _predecir(z_train[:, cols], y_train["estacion"], z_test[:, cols], plano.clases)
    metricas["plano_estacion"] = float(np.mean(np.where(i >= 0, np.array(plano.clases)[i], None) == y_test["estacion"]))

    # Media sin recorte (como la tesis de Dinh) frente a lo elegido (A.5).
    dinh = next(c for c in candidatos if c["muestreo"] == ("media_p0_100", "media_p0_100"))
    metricas["cv_media_sin_recorte"] = dinh["cv_estacion"]
    metricas["cv_elegido"] = elegido["cv_estacion"]

    # Equidad: proxy ITA de la piel medida.
    bandas = np.array([banda_ita(v) for v in ita(x_test)])
    metricas["equidad_ita"] = {}
    for nombre in [b[0] for b in BANDAS_ITA] + ["sin_piel"]:
        m = bandas == nombre
        if m.sum() == 0:
            continue
        metricas["equidad_ita"][nombre] = {
            "n": int(m.sum()),
            "estacion": float(np.mean(primera[m] == y_test["estacion"][m])),
            "subtono": float(np.mean(capas["subtono"][m] == y_test["subtono"][m])),
            "contraste": float(np.mean(capas["contraste"][m] == y_test["contraste"][m])),
        }

    # Estabilidad: misma estacion con la imagen perturbada.
    ruta_pert = rutas.salida / "regiones_perturbadas.csv"
    if ruta_pert.exists():
        por_id = dict(zip([f["id"] for f in test], primera))
        perturbadas = leer(ruta_pert)
        metricas["estabilidad"] = {}
        for nombre in PERTURBACIONES:
            sub = [f for f in perturbadas if f["perturbacion"] == nombre]
            p1, _, _, _ = predecir_test(modelo, matriz(sub, elegido["muestreo"]))
            base = np.array([por_id[f["id"]] for f in sub])
            iguales = (p1 == base) & (base != None)  # noqa: E711
            metricas["estabilidad"][nombre] = {
                "n": len(sub),
                "misma_estacion": float(iguales.mean()),
                "exactitud": float(np.mean(p1 == np.array([f["estacion"] for f in sub]))),
            }

    manifiesto = json.loads((rutas.salida / "manifiesto.json").read_text(encoding="utf-8"))
    artefacto = {
        **modelo.a_dict(),
        "creado": datetime.now(UTC).isoformat(timespec="seconds"),
        "semilla": SEMILLA,
        "experimental": "Solo MVP academico: derivado de Deep Armocromia (CelebA). Uso comercial no permitido.",
        "dataset": {
            "nombre": manifiesto["dataset"],
            "hash_manifiesto": manifiesto["hash_manifiesto"],
            "conteo": manifiesto["conteo"],
        },
        "muestreo": {
            "piel_y_cabello": elegido["muestreo"][0],
            "ojos": elegido["muestreo"][1],
            "pixeles_minimos": MINIMOS,
        },
        "segmentacion": {
            **asdict(ParametrosSegmentacion()),
            "modelos": manifiesto["modelos_mediapipe"],
        },
        "metricas_test": {
            k: metricas[k] for k in ("cobertura", "estacion", "subtono", "contraste", "top2")
        },
    }
    (rutas.salida / f"centroides-{VERSION}.json").write_text(
        json.dumps(artefacto, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    (rutas.salida / "metricas.json").write_text(
        json.dumps({"elegido": elegido, "candidatos": candidatos, "test": metricas}, indent=2),
        encoding="utf-8",
    )
    (rutas.salida / "informe.md").write_text(informe(elegido, metricas, manifiesto), encoding="utf-8")
    print(informe(elegido, metricas, manifiesto))
    return 0


def _pct(x: float) -> str:
    return f"{100 * x:.1f} %"


def informe(elegido: dict, m: dict, manifiesto: dict) -> str:
    lineas = [
        f"# Centroides {VERSION}: informe",
        "",
        f"Dataset: {manifiesto['dataset']}. Hash del manifiesto `{manifiesto['hash_manifiesto']}`.",
        f"Muestreo elegido: piel y cabello `{elegido['muestreo'][0]}`, ojos `{elegido['muestreo'][1]}`.",
        "",
        "## Variables por capa",
        "",
        *[f"- **{c}**: {', '.join(elegido['variables'][c])}" for c in CAPAS],
        "",
        "## Prueba (RNF07, E.29)",
        "",
        "| Metrica | Exactitud | IC 95 % | Referencia publicada |",
        "|---|---|---|---|",
        f"| 4 estaciones | {_pct(m['estacion']['exactitud'])} | {_pct(m['estacion']['ic95'][0])} - {_pct(m['estacion']['ic95'][1])} | ~54 % |",
        f"| Subtono | {_pct(m['subtono']['exactitud'])} | {_pct(m['subtono']['ic95'][0])} - {_pct(m['subtono']['ic95'][1])} | ~70 % |",
        f"| Contraste | {_pct(m['contraste']['exactitud'])} | {_pct(m['contraste']['ic95'][0])} - {_pct(m['contraste']['ic95'][1])} | ~76 % |",
        f"| Top-2 | {_pct(m['top2']['exactitud'])} | {_pct(m['top2']['ic95'][0])} - {_pct(m['top2']['ic95'][1])} | n/d |",
        "",
        f"Cobertura (imagenes clasificables): {_pct(m['cobertura'])}. Las no clasificables cuentan como error.",
        f"Linea base plana (4 centroides, mismo muestreo): {_pct(m['plano_estacion'])}.",
        f"CV en train, media sin recorte (Dinh) frente a lo elegido: {_pct(m['cv_media_sin_recorte'])} / {_pct(m['cv_elegido'])}.",
        "",
        "## Matriz de confusion (filas: real; columnas: predicha)",
        "",
        "| | " + " | ".join(ESTACIONES) + " |",
        "|---|" + "---|" * len(ESTACIONES),
        *[f"| {r} | " + " | ".join(str(m["confusion"][r][p]) for p in ESTACIONES) + " |" for r in ESTACIONES],
        "",
        "## Equidad (proxy ITA, no Monk)",
        "",
        "| Banda ITA | n | Estacion | Subtono | Contraste |",
        "|---|---|---|---|---|",
        *[
            f"| {b} | {v['n']} | {_pct(v['estacion'])} | {_pct(v['subtono'])} | {_pct(v['contraste'])} |"
            for b, v in m["equidad_ita"].items()
        ],
    ]
    if "estabilidad" in m:
        lineas += [
            "",
            "## Estabilidad (proxy: perturbaciones de la misma imagen)",
            "",
            "| Perturbacion | Misma estacion | Exactitud |",
            "|---|---|---|",
            *[
                f"| {p} | {_pct(v['misma_estacion'])} | {_pct(v['exactitud'])} |"
                for p, v in m["estabilidad"].items()
            ],
        ]
    return "\n".join(lineas) + "\n"


if __name__ == "__main__":
    sys.exit(principal())
