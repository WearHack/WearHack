"""Paso 2: metricas M1-M6 y veredicto, a partir de `mediciones.csv`.

    python -m normalizacion.analizar [--max-quemados 2 --max-negros 1 --min-nitidez 50 --min-ancho 200]

Escribe `resultados.json` e `informe.md` en la carpeta de salida.

Decisiones que toma el codigo y que hay que leer junto al protocolo:

- M1 y M2 comparan **todas las parejas de fotos de la misma persona** con luz
  normal (`VEN`, `LEDC`, `LEDF`), de cualquier celular y repeticion.
- M2 se da de dos formas: con la frontera del protocolo (la mediana del grupo,
  de `piel_calidez` para el subtono y de `contraste`) y con la decision de los
  centroides `4-estaciones-v1`, que no existian cuando se escribio el protocolo.
  **El veredicto usa la del protocolo**; la otra se reporta.
- REF es el mejor caso (tarjeta en el encuadre) y no es una opcion del
  producto: se mide, pero no se puede elegir.
- Criterios obligatorios: el principal y el de equidad. El secundario (M1 de
  piel, p90, al menos un 30 % menor que T0) se reporta.
- Sin `grupos_tono` la equidad queda sin evaluar y el veredicto es provisional.
- Cobertura: la fraccion de tomas en que la tecnica pudo estimar la luz. Una
  tecnica que solo funciona en las fotos faciles se veria mejor de lo que es;
  por debajo del 90 % el veredicto lo dice.
"""

import argparse
import csv
import itertools
import json
import math
import sys
from collections import defaultdict

import numpy as np

from normalizacion import configuracion
from normalizacion.configuracion import grupo_de_tono
from normalizacion.lotes import LUCES_NORMALES
from normalizacion.metricas import delta_e_00, ita, spearman
from normalizacion.tecnicas import NEUTRA, angulo

from app.extraccion.variables import REGIONES

ELEGIBLES = ("T0", "T1", "T2")  # de mas simple a mas compleja; REF no es del producto
MAX_M2 = 0.10
MAX_BRECHA_EQUIDAD = 0.05
MEJORA_M1 = 0.30
COBERTURA_MINIMA = 0.90


def _flotante(valor: str) -> float:
    return float(valor) if valor not in ("", None) else math.nan


def leer(ruta) -> list[dict]:
    with open(ruta, newline="", encoding="utf-8") as f:
        filas = list(csv.DictReader(f))
    numericas = [c for c in filas[0] if c.endswith(("_L", "_a", "_b", "_n", "_pct"))] if filas else []
    numericas += ["luz_r", "luz_g", "luz_b", "ref_r", "ref_g", "ref_b", "piel_calidez",
                  "contraste", "nitidez", "ancho_rostro"]  # fmt: skip
    for f in filas:
        for c in numericas:
            if c in f:
                f[c] = _flotante(f[c])
        f["monk"] = int(f["monk"]) if f.get("monk") else None
    return filas


def _validas(filas: list[dict], tecnica: str, fuente: str = "sesion") -> list[dict]:
    return [f for f in filas if f["tecnica"] == tecnica and f["fuente"] == fuente and not f["motivo"]]


def _percentiles(valores) -> dict:
    v = np.asarray([x for x in valores if not math.isnan(x)])
    if len(v) == 0:
        return {"p50": None, "p90": None, "n": 0}
    return {"p50": float(np.percentile(v, 50)), "p90": float(np.percentile(v, 90)), "n": len(v)}


def _lab(fila: dict, region: str) -> np.ndarray | None:
    lab = [fila.get(f"{region}_{c}") for c in "Lab"]
    return None if any(v is None or math.isnan(v) for v in lab) else np.array(lab)


def parejas(filas: list[dict]):
    """Parejas de fotos de la misma persona."""
    por_persona = defaultdict(list)
    for f in filas:
        por_persona[f["seudonimo"]].append(f)
    for fotos in por_persona.values():
        yield from itertools.combinations(fotos, 2)


def m1(filas: list[dict]) -> dict:
    """ΔE00 entre las fotos de cada persona, por region."""
    salida = {}
    for region in REGIONES:
        deltas = []
        for a, b in parejas(filas):
            la, lb = _lab(a, region), _lab(b, region)
            if la is not None and lb is not None:
                deltas.append(float(delta_e_00(la, lb)))
        salida[region] = _percentiles(deltas)
    return salida


def _tasa_cambio(filas: list[dict], decision) -> dict:
    distintas = total = 0
    for a, b in parejas(filas):
        da, db = decision(a), decision(b)
        if da is None or db is None:
            continue
        total += 1
        distintas += da != db
    return {"tasa": distintas / total if total else None, "parejas": total}


def m2(filas: list[dict], fronteras: dict[str, float]) -> dict:
    """Cambio de decision de subtono y de contraste entre parejas de la misma persona."""

    def lado(variable):
        def decidir(f):
            v = f.get(variable)
            return None if v is None or math.isnan(v) else v >= fronteras[variable]

        return decidir

    return {
        "mediana": {
            "subtono": _tasa_cambio(filas, lado("piel_calidez")),
            "contraste": _tasa_cambio(filas, lado("contraste")),
        },
        "centroides": {
            "subtono": _tasa_cambio(filas, lambda f: f.get("subtono") or None),
            "contraste": _tasa_cambio(filas, lambda f: f.get("clase_contraste") or None),
        },
    }


def fronteras_de(filas: list[dict]) -> dict[str, float]:
    """La mediana del grupo (protocolo, M2): frontera provisional para esta prueba."""
    salida = {}
    for variable in ("piel_calidez", "contraste"):
        v = [f[variable] for f in filas if not math.isnan(f.get(variable, math.nan))]
        salida[variable] = float(np.median(v)) if v else math.nan
    return salida


def m3(filas: list[dict], tecnica: str) -> dict:
    """Angulo entre la luz estimada y la de la tarjeta, en las fotos con tarjeta marcada."""
    angulos = []
    for f in filas:
        if f["tecnica"] != tecnica or f["fuente"] != "sesion" or f["motivo"]:
            continue
        ref = np.array([f.get("ref_r"), f.get("ref_g"), f.get("ref_b")], dtype=float)
        if np.isnan(ref).any():
            continue
        luz = np.array([f["luz_r"], f["luz_g"], f["luz_b"]], dtype=float)
        angulos.append(angulo(NEUTRA if tecnica == "T0" else luz, ref))
    return _percentiles(angulos)


def m4(filas: list[dict], tecnica: str) -> dict:
    """Spearman entre el tono de piel corregido y la escala Monk (MST-E)."""
    mst = [f for f in _validas(filas, tecnica, "mst_e") if f["monk"] is not None]
    if not mst:
        return {"omitida": "sin MST-E"}
    monk = [f["monk"] for f in mst]
    return {
        "ita": spearman([ita(f["piel_L"], f["piel_b"]) for f in mst], monk),
        "L": spearman([f["piel_L"] for f in mst], monk),
        "n": len(mst),
    }


def m6(filas: list[dict], umbrales: dict) -> dict:
    """Fotos que fallan los controles de calidad, por luz y por celular.

    Los controles son del recorte y no dependen de la tecnica: se cuenta una
    fila por toma (la de T0). Sin umbrales, solo se reportan las medianas.
    """
    tomas = [f for f in filas if f["tecnica"] == "T0" and f["fuente"] == "sesion"]

    def falla(f) -> bool:
        return (
            (umbrales.get("max_quemados") is not None and f["quemados_pct"] > umbrales["max_quemados"])
            or (umbrales.get("max_negros") is not None and f["negros_pct"] > umbrales["max_negros"])
            or (umbrales.get("min_nitidez") is not None and f["nitidez"] < umbrales["min_nitidez"])
            or (umbrales.get("min_ancho") is not None and f["ancho_rostro"] < umbrales["min_ancho"])
        )

    salida = {}
    for clave in ("luz", "celular"):
        grupos = defaultdict(list)
        for f in tomas:
            grupos[f[clave]].append(f)
        salida[clave] = {
            valor: {
                "rechazo": float(np.mean([falla(f) for f in fs])) if any(umbrales.values()) else None,
                "quemados_pct_mediana": float(np.median([f["quemados_pct"] for f in fs])),
                "negros_pct_mediana": float(np.median([f["negros_pct"] for f in fs])),
                "nitidez_mediana": float(np.median([f["nitidez"] for f in fs])),
                "n": len(fs),
            }
            for valor, fs in sorted(grupos.items())
        }
    return salida


def ruido_repeticion(filas: list[dict]) -> dict:
    """ΔE00 de piel entre R2 y R3 de la misma persona, luz y celular."""
    por_condicion = defaultdict(dict)
    for f in filas:
        if f["repeticion"] in ("R2", "R3"):
            por_condicion[(f["seudonimo"], f["luz"], f["celular"])][f["repeticion"]] = f
    deltas = []
    for par in por_condicion.values():
        if "R2" in par and "R3" in par:
            a, b = _lab(par["R2"], "piel"), _lab(par["R3"], "piel")
            if a is not None and b is not None:
                deltas.append(float(delta_e_00(a, b)))
    return _percentiles(deltas)


def evaluar(filas: list[dict], tecnica: str, umbrales: dict) -> dict:
    todas = [f for f in filas if f["tecnica"] == tecnica and f["fuente"] == "sesion"]
    validas = _validas(filas, tecnica)
    normales = [f for f in validas if f["luz"] in LUCES_NORMALES]
    fronteras = fronteras_de(normales)
    por_grupo = {}
    for grupo in ("1-3", "4-7", "8-10"):
        del_grupo = [f for f in normales if f["monk"] is not None and grupo_de_tono(f["monk"]) == grupo]
        if del_grupo:
            por_grupo[grupo] = {
                "personas": len({f["seudonimo"] for f in del_grupo}),
                "m1": m1(del_grupo),
                "m2": m2(del_grupo, fronteras),
            }
    return {
        "cobertura": len(validas) / len(todas) if todas else None,
        "fronteras_m2": fronteras,
        "m1": m1(normales),
        "m1_todas_las_luces": m1(validas),
        "m2": m2(normales, fronteras),
        "m3": m3(filas, tecnica),
        "m4": m4(filas, tecnica),
        "m5": por_grupo,
        "ruido_repeticion": ruido_repeticion(validas),
    }


def veredicto(por_tecnica: dict) -> dict:
    """Los criterios del protocolo (seccion 6) y la tecnica elegida."""
    t0_p90 = por_tecnica["T0"]["m1"]["piel"]["p90"]
    salida = {"tecnicas": {}, "elegida": None, "avisos": []}
    for tecnica, r in por_tecnica.items():
        m2_ = r["m2"]["mediana"]
        tasas = [m2_["subtono"]["tasa"], m2_["contraste"]["tasa"]]
        principal = all(t is not None and t <= MAX_M2 for t in tasas)
        grupos = r["m5"]
        for g in grupos.values():
            g_tasas = [g["m2"]["mediana"][v]["tasa"] for v in ("subtono", "contraste")]
            principal = principal and all(t is not None and t <= MAX_M2 for t in g_tasas)
        if len(grupos) >= 2:
            brechas = []
            for v in ("subtono", "contraste"):
                ts = [g["m2"]["mediana"][v]["tasa"] for g in grupos.values()]
                ts = [t for t in ts if t is not None]
                brechas.append(max(ts) - min(ts) if ts else math.inf)
            equidad = max(brechas) <= MAX_BRECHA_EQUIDAD
        else:
            equidad = None  # sin evaluar
        p90 = r["m1"]["piel"]["p90"]
        secundario = (
            p90 <= (1 - MEJORA_M1) * t0_p90 if tecnica != "T0" and p90 is not None and t0_p90 else None
        )
        cobertura_ok = r["cobertura"] is not None and r["cobertura"] >= COBERTURA_MINIMA
        salida["tecnicas"][tecnica] = {
            "principal": principal,
            "equidad": equidad,
            "secundario": secundario,
            "cobertura_suficiente": cobertura_ok,
            "cumple": principal and equidad is not False and cobertura_ok,
        }
    for tecnica in ELEGIBLES:
        if tecnica in salida["tecnicas"] and salida["tecnicas"][tecnica]["cumple"]:
            salida["elegida"] = tecnica
            break
    if salida["elegida"] is None:
        salida["avisos"].append("Ninguna de T0-T2 cumple: el protocolo pide evaluar T3 y, si no, T4.")
    if any(v["equidad"] is None for v in salida["tecnicas"].values()):
        salida["avisos"].append(
            "Equidad sin evaluar (menos de dos grupos de tono con datos): veredicto provisional."
        )
    return salida


def _fmt(v, porcentaje=False) -> str:
    if v is None or (isinstance(v, float) and math.isnan(v)):
        return "-"
    return f"{v:.1%}" if porcentaje else f"{v:.2f}"


def informe(resultados: dict) -> str:
    ver = resultados["veredicto"]
    lineas = [
        "# Normalizacion de color: resultados (#66)",
        "",
        f"Tomas: {resultados['tomas']} (D3 incluido: {resultados['incluye_d3']}). "
        f"Tecnica elegida: **{ver['elegida'] or 'ninguna'}**.",
        "",
        *[f"- {a}" for a in ver["avisos"]],
        "",
        "| Tecnica | Cobertura | M1 piel p50 | M1 piel p90 | M2 subtono | M2 contraste | M2 subtono (centroides) | M3 p50 (grados) | Cumple |",
        "|---|---|---|---|---|---|---|---|---|",
    ]  # fmt: skip
    for t, r in resultados["tecnicas"].items():
        m2_ = r["m2"]
        lineas.append(
            f"| {t} | {_fmt(r['cobertura'], True)} | {_fmt(r['m1']['piel']['p50'])} | "
            f"{_fmt(r['m1']['piel']['p90'])} | {_fmt(m2_['mediana']['subtono']['tasa'], True)} | "
            f"{_fmt(m2_['mediana']['contraste']['tasa'], True)} | "
            f"{_fmt(m2_['centroides']['subtono']['tasa'], True)} | {_fmt(r['m3']['p50'])} | "
            f"{'si' if ver['tecnicas'][t]['cumple'] else 'no'} |"
        )
    lineas += ["", "Detalle completo (M4, M5, M6 y ruido de repeticion) en `resultados.json`."]
    return "\n".join(lineas) + "\n"


def analizar(filas: list[dict], umbrales: dict, incluye_d3: bool = False) -> dict:
    tecnicas = sorted({f["tecnica"] for f in filas}, key=["T0", "T1", "T2", "REF"].index)
    por_tecnica = {t: evaluar(filas, t, umbrales) for t in tecnicas}
    return {
        "tomas": len({f["id"] for f in filas if f["fuente"] == "sesion"}),
        "incluye_d3": incluye_d3,
        "umbrales_calidad": umbrales,
        "m6": m6(filas, umbrales),
        "tecnicas": por_tecnica,
        "veredicto": veredicto(por_tecnica),
    }


def principal(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--max-quemados", type=float)
    parser.add_argument("--max-negros", type=float)
    parser.add_argument("--min-nitidez", type=float)
    parser.add_argument("--min-ancho", type=float)
    args = parser.parse_args(argv)
    umbrales = {
        "max_quemados": args.max_quemados,
        "max_negros": args.max_negros,
        "min_nitidez": args.min_nitidez,
        "min_ancho": args.min_ancho,
    }

    rutas = configuracion.cargar()
    filas = leer(rutas.mediciones)
    resultados = analizar(filas, umbrales, incluye_d3=any(f["celular"] == "D3" for f in filas))
    (rutas.salida / "resultados.json").write_text(
        json.dumps(resultados, indent=2, default=float), encoding="utf-8"
    )
    texto = informe(resultados)
    (rutas.salida / "informe.md").write_text(texto, encoding="utf-8")
    print(texto)
    return 0


if __name__ == "__main__":
    sys.exit(principal())
