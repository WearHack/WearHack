"""Paso 1: mide cada toma con cada tecnica y escribe `mediciones.csv`.

    python -m normalizacion.extraer [--incluir-d3]

Por toma:

1. Segmenta el **recorte** (lo que el producto analiza) una sola vez, con la
   segmentacion y los parametros del artefacto de centroides.
2. Para cada tecnica estima la luz, corrige el recorte en RGB lineal y vuelve a
   muestrear las mismas mascaras: la segmentacion no cambia con la correccion.
3. Clasifica subtono y contraste con los centroides, para M2.

REF solo existe en las tomas `R1` con la tarjeta marcada (`marcar_tarjeta`).
Una tecnica que no puede estimar la luz (ojo cerrado, sin brillos) deja la fila
con su motivo: cuenta en el reporte, no se descarta en silencio.
"""

import argparse
import csv
import json
import math
import sys

import numpy as np

from normalizacion import configuracion, lotes
from normalizacion.imagenes import leer_srgb
from normalizacion.metricas import calidad
from normalizacion.tarjeta import PARCHES, cargar_cajas, medir
from normalizacion.tecnicas import (
    TECNICAS,
    corregir,
    estimar_ref,
    estimar_t0,
    estimar_t1,
    estimar_t2,
)

from app.centroides import Artefacto
from app.extraccion.muestreo import muestrear_regiones
from app.extraccion.segmentacion import SegmentadorRostro, SinRostro
from app.extraccion.variables import REGIONES, calcular_variables

COLUMNAS = [
    "fuente", "id", "seudonimo", "luz", "celular", "repeticion", "tarjeta", "monk",
    "tecnica", "motivo",
    "luz_r", "luz_g", "luz_b", "ref_r", "ref_g", "ref_b",
    *(f"{r}_{c}" for r in REGIONES for c in ("L", "a", "b", "n")),
    "piel_calidez", "contraste", "subtono", "clase_contraste", "estacion",
    "quemados_pct", "negros_pct", "nitidez", "ancho_rostro",
]  # fmt: skip


def _num(v: float | None) -> str:
    return "" if v is None or (isinstance(v, float) and math.isnan(v)) else f"{v:.6f}"


def medir_toma(
    recorte: np.ndarray,
    segmentador,
    artefacto: Artefacto,
    luz_ref: np.ndarray | None,
) -> tuple[list[dict], dict]:
    """Una fila parcial por tecnica, mas la calidad del recorte."""
    controles = calidad(recorte)
    try:
        reg = segmentador.regiones(recorte)
    except SinRostro:
        return [{"tecnica": t, "motivo": "sin_rostro"} for t in TECNICAS], controles
    mascaras = {"piel": reg.piel, "cabello": reg.cabello, "ojos": reg.ojos}
    luces = {
        "T0": estimar_t0(),
        "T1": estimar_t1(reg.rgb, reg.esclerotica),
        "T2": estimar_t2(reg.rgb, reg.piel, reg.ojos),
        "REF": estimar_ref(luz_ref),
    }
    filas = []
    for tecnica in TECNICAS:
        luz = luces[tecnica]
        if luz is None:
            motivo = "sin_tarjeta" if tecnica == "REF" else "sin_referencia"
            filas.append({"tecnica": tecnica, "motivo": motivo})
            continue
        corregida = corregir(reg.rgb, luz)
        muestras = muestrear_regiones(corregida, mascaras, artefacto.variantes, artefacto.minimos)
        variables = calcular_variables(muestras)
        resultado = artefacto.clasificador.clasificar(variables)
        fila = {"tecnica": tecnica, "motivo": "" if resultado else "sin_clasificacion"}
        fila.update({"luz_r": luz[0], "luz_g": luz[1], "luz_b": luz[2]})
        for r in REGIONES:
            m = muestras[r]
            fila.update(
                {f"{r}_L": m.L, f"{r}_a": m.a, f"{r}_b": m.b, f"{r}_n": m.pixeles} if m else {f"{r}_n": 0}
            )
        fila["piel_calidez"] = variables.get("piel_calidez")
        fila["contraste"] = variables.get("contraste")
        if resultado:
            probs = resultado.capas
            fila["subtono"] = max(probs["subtono"], key=probs["subtono"].get)
            fila["clase_contraste"] = max(probs["contraste"], key=probs["contraste"].get)
            fila["estacion"] = resultado.estacion
        filas.append(fila)
    return filas, controles


def _escribir(escritor, base: dict, filas: list[dict], controles: dict, luz_ref) -> None:
    for fila in filas:
        completa = {**base, **fila, **controles}
        if luz_ref is not None:
            completa.update({"ref_r": luz_ref[0], "ref_g": luz_ref[1], "ref_b": luz_ref[2]})
        escritor.writerow(
            {c: _num(v) if isinstance(v, float) else ("" if v is None else v)
             for c, v in ((c, completa.get(c)) for c in COLUMNAS)}
        )  # fmt: skip


def _mst_e(rutas: configuracion.Rutas) -> list[tuple[str, int]]:
    if rutas.mst_e is None:
        return []
    with rutas.mst_e.etiquetas.open(newline="", encoding="utf-8") as f:
        return [(r["archivo"], int(r["monk"])) for r in csv.DictReader(f)]


def principal(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--incluir-d3", action="store_true", help="El celular reservado (validacion final)")
    args = parser.parse_args(argv)

    rutas = configuracion.cargar()
    artefacto = Artefacto.desde_dict(json.loads(rutas.artefacto.read_text(encoding="utf-8")))
    carga = lotes.cargar(rutas.lotes, incluir_d3=args.incluir_d3)
    cajas = cargar_cajas(rutas.tarjetas)
    grupos = configuracion.cargar_grupos_tono(rutas.grupos_tono)
    for p in carga.problemas:
        print(f"AVISO {p}", file=sys.stderr)
    print(f"{len(carga.tomas)} tomas ({carga.excluidas_d3} de D3 excluidas)", flush=True)

    with (
        SegmentadorRostro(
            rutas.modelos_mediapipe / "face_landmarker.task",
            rutas.modelos_mediapipe / "selfie_multiclass_256x256.tflite",
            artefacto.segmentacion,
        ) as segmentador,
        rutas.mediciones.open("w", newline="", encoding="utf-8") as f,
    ):
        escritor = csv.DictWriter(f, fieldnames=COLUMNAS)
        escritor.writeheader()
        for i, toma in enumerate(carga.tomas, 1):
            luz_ref = None
            if toma.tarjeta and toma.id in cajas:
                foto = leer_srgb(toma.foto)
                parches = {p: medir(foto, c) for p, c in cajas[toma.id].items() if p in PARCHES}
                luz_ref = parches["gris"].lineal if "gris" in parches else None
            filas, controles = medir_toma(leer_srgb(toma.recorte), segmentador, artefacto, luz_ref)
            base = {
                "fuente": "sesion", "id": toma.id, "seudonimo": toma.seudonimo, "luz": toma.luz,
                "celular": toma.celular, "repeticion": toma.repeticion,
                "tarjeta": int(toma.tarjeta), "monk": grupos.get(toma.seudonimo, ""),
                "ancho_rostro": toma.ancho_rostro,
            }  # fmt: skip
            _escribir(escritor, base, filas, controles, luz_ref)
            if i % 20 == 0:
                print(f"  {i}/{len(carga.tomas)}", flush=True)

        for archivo, monk in _mst_e(rutas):
            imagen = leer_srgb(rutas.mst_e.imagenes / archivo)
            filas, controles = medir_toma(imagen, segmentador, artefacto, None)
            _escribir(escritor, {"fuente": "mst_e", "id": archivo, "monk": monk}, filas, controles, None)

    print(f"Escrito {rutas.mediciones}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(principal())
