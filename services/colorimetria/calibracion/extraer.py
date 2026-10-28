"""Paso 1: pasa cada imagen por el pipeline y guarda el color de cada region.

    python -m calibracion.extraer                       # train y test
    python -m calibracion.extraer --perturbaciones      # test, con cada perturbacion

Guarda, por imagen, region y variante de muestreo, L, a, b, S, V y el numero de
pixeles. Las variables y el minimo de pixeles se aplican despues, en
`calibrar`, para poder elegirlos por validacion cruzada sin volver a segmentar.

Tambien escribe el manifiesto del dataset (SHA-256 de cada imagen), que es lo
que se anota en la procedencia.

Pillow y MediaPipe (extra `calibracion`) se importan dentro de las funciones:
los tests importan este modulo sin ellos.
"""

import argparse
import csv
import io
import json
import math
import os
import sys
import time
from multiprocessing import Pool

import numpy as np

from app.extraccion.color import lineal_a_srgb, srgb_a_lineal
from app.extraccion.muestreo import CANALES, Variante, muestrear, pixeles_de_region
from app.extraccion.segmentacion import SegmentadorRostro, SinRostro
from calibracion import configuracion, dataset

# Variantes candidatas. La de los ojos es mas agresiva (respuestas A.7).
VARIANTES = {
    "piel": [
        Variante("media"),
        Variante("mediana"),
        Variante("mediana", 5, 95),
        Variante("mediana", 10, 90),
        Variante("mediana", 20, 80),
    ],
    "ojos": [
        Variante("media"),
        Variante("mediana", 10, 90),
        Variante("mediana", 20, 80),
        Variante("mediana", 30, 70),
    ],
}
VARIANTES["cabello"] = VARIANTES["piel"]
REGIONES = ("piel", "cabello", "ojos")


def _ganancia(rgb: np.ndarray, r: float, g: float, b: float) -> np.ndarray:
    lineal = srgb_a_lineal(rgb) * np.array([r, g, b])
    return np.round(lineal_a_srgb(lineal)).astype(np.uint8)


def _jpeg(rgb: np.ndarray, calidad: int) -> np.ndarray:
    from PIL import Image

    buf = io.BytesIO()
    Image.fromarray(rgb).save(buf, format="JPEG", quality=calidad)
    return np.asarray(Image.open(buf).convert("RGB"))


def _escala(rgb: np.ndarray, factor: float) -> np.ndarray:
    from PIL import Image

    im = Image.fromarray(rgb)
    tam = (max(1, round(im.width * factor)), max(1, round(im.height * factor)))
    return np.asarray(im.resize(tam, Image.Resampling.LANCZOS))


# Proxy de estabilidad por persona (E.29): Deep Armocromia no trae varias fotos
# de la misma persona con luces distintas. Las ganancias van en RGB lineal.
PERTURBACIONES = {
    "exposicion_mas": lambda x: _ganancia(x, 1.15, 1.15, 1.15),
    "exposicion_menos": lambda x: _ganancia(x, 0.85, 0.85, 0.85),
    "luz_calida": lambda x: _ganancia(x, 1.06, 1.0, 0.94),
    "luz_fria": lambda x: _ganancia(x, 0.94, 1.0, 1.06),
    "jpeg_70": lambda x: _jpeg(x, 70),
    "escala_50": lambda x: _escala(x, 0.5),
}


def columnas() -> list[str]:
    cols = ["id", "particion", "estacion", "subtipo", "perturbacion", "fallo", "ancho_rostro"]
    for region in REGIONES:
        for v in VARIANTES[region]:
            cols += [f"{region}__{v.nombre}__{c}" for c in (*CANALES, "n")]
    return cols


_segmentador: SegmentadorRostro | None = None


def _iniciar(ruta_landmarker: str, ruta_segmentador: str) -> None:
    global _segmentador
    _segmentador = SegmentadorRostro(ruta_landmarker, ruta_segmentador)


def _procesar(tarea: tuple[dataset.Imagen, str]) -> dict:
    from PIL import Image

    imagen, perturbacion = tarea
    fila = {
        "id": imagen.id,
        "particion": imagen.particion,
        "estacion": imagen.estacion,
        "subtipo": imagen.subtipo,
        "perturbacion": perturbacion,
        "fallo": "",
        "ancho_rostro": "",
    }
    rgb = np.asarray(Image.open(imagen.ruta).convert("RGB"))
    if perturbacion:
        rgb = PERTURBACIONES[perturbacion](rgb)
    try:
        regiones = _segmentador.regiones(rgb)
    except SinRostro:
        fila["fallo"] = "sin_rostro"
        return fila
    fila["ancho_rostro"] = f"{regiones.ancho_rostro:.1f}"
    for region in REGIONES:
        lab, hsv = pixeles_de_region(regiones.rgb, getattr(regiones, region))
        for v in VARIANTES[region]:
            m = muestrear(lab, hsv, v, minimo_pixeles=1)
            prefijo = f"{region}__{v.nombre}__"
            for c in CANALES:
                fila[prefijo + c] = f"{getattr(m, c):.4f}" if m else ""
            fila[prefijo + "n"] = m.pixeles if m else 0
    return fila


def escribir_manifiesto(rutas: configuracion.Rutas, imagenes: list[dataset.Imagen]) -> dict:
    filas = [(i.id, dataset.sha256(i.ruta)) for i in imagenes]
    conteo: dict[str, dict[str, int]] = {}
    for i in imagenes:
        conteo.setdefault(i.particion, {}).setdefault(i.estacion, 0)
        conteo[i.particion][i.estacion] += 1
    manifiesto = {
        "dataset": "Deep Armocromia (Stacchio et al., ECCV Workshops 2024)",
        "imagenes": len(filas),
        "conteo": conteo,
        "hash_manifiesto": dataset.hash_del_manifiesto(filas),
        "modelos_mediapipe": {
            p.name: dataset.sha256(p) for p in (rutas.landmarker, rutas.segmentador)
        },
    }
    (rutas.salida / "manifiesto.json").write_text(
        json.dumps(manifiesto, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    with (rutas.salida / "manifiesto.sha256").open("w", encoding="utf-8") as f:
        f.writelines(f"{h}  {i}\n" for i, h in sorted(filas))
    return manifiesto


def principal(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--perturbaciones", action="store_true")
    parser.add_argument("--procesos", type=int, default=max(1, (os.cpu_count() or 2) - 2))
    parser.add_argument("--limite", type=int, default=0, help="Solo para probar el pipeline")
    args = parser.parse_args(argv)

    rutas = configuracion.cargar()
    imagenes = dataset.listar(rutas.deep_armocromia)
    if args.limite:
        imagenes = imagenes[:: math.ceil(len(imagenes) / args.limite)]

    if args.perturbaciones:
        tareas = [(i, p) for i in imagenes if i.particion == "test" for p in PERTURBACIONES]
        destino = rutas.salida / "regiones_perturbadas.csv"
    else:
        manifiesto = escribir_manifiesto(rutas, imagenes)
        print(f"Manifiesto: {manifiesto['imagenes']} imagenes, {manifiesto['hash_manifiesto']}")
        tareas = [(i, "") for i in imagenes]
        destino = rutas.salida / "regiones.csv"

    inicio = time.monotonic()
    temporal = destino.with_suffix(".tmp")
    with (
        temporal.open("w", newline="", encoding="utf-8") as f,
        Pool(args.procesos, _iniciar, (str(rutas.landmarker), str(rutas.segmentador))) as pool,
    ):
        escritor = csv.DictWriter(f, fieldnames=columnas())
        escritor.writeheader()
        fallos = 0
        for n, fila in enumerate(pool.imap(_procesar, tareas, chunksize=8), start=1):
            escritor.writerow(fila)
            fallos += bool(fila["fallo"])
            if n % 250 == 0 or n == len(tareas):
                print(f"{n}/{len(tareas)}  fallos={fallos}  {time.monotonic() - inicio:.0f}s")
    temporal.replace(destino)
    print(f"Escrito {destino}")
    return 0


if __name__ == "__main__":
    sys.exit(principal())
