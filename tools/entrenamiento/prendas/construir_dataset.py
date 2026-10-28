"""Paso 2: recortes de prenda etiquetados con tipo y patron de C.18.

    python tools/entrenamiento/prendas/construir_dataset.py

- **Fashionpedia**: cada prenda se recorta con su mascara sobre fondo blanco,
  para parecerse a lo que entregara u2netp en el telefono. train2020 se parte
  90/10 por imagen en entrenamiento y validacion; val2020 es la prueba.
- **Clothing dataset (Grigorev)**: fotos de prendas sueltas, el dominio de la
  app. Solo aportan tipo. Se parten 80/10/10 por persona que las envio, para que
  la misma prenda no caiga en dos particiones.

Escribe `<salida>/dataset/imagenes/*.jpg` y `<salida>/dataset/manifiesto.csv`, con
la licencia de cada imagen de origen. Las anotaciones de entrenamiento pesan
540 MB: se leen en streaming con ijson, en dos pasadas, porque cargarlas enteras
no cabe en la memoria de un portatil de 8 GB.
"""

from __future__ import annotations

import collections
import csv
import json
import random
import sys
from pathlib import Path

import ijson
import numpy as np
from PIL import Image
from pycocotools import mask as mascara_coco

sys.path.insert(0, str(Path(__file__).resolve().parent))

import configuracion  # noqa: E402
import mapeo  # noqa: E402

SEMILLA = 42
LADO = 256  # lado mayor del recorte guardado; el modelo entrena a 224
MARGEN = 0.08  # del lado mayor de la caja
LADO_MINIMO = 24  # cajas mas pequenas no tienen informacion util
# Tope por tipo para que el calzado (decenas de miles) no ahogue al resto.
TOPE = {"train": 5000, "val": 600}
FRACCION_VAL = 0.10


# --------------------------------------------------------------------------- #
# Fashionpedia
# --------------------------------------------------------------------------- #


def _ontologia(ruta_json: Path) -> tuple[dict[int, str], dict[int, str], dict[int, int]]:
    """Tipo por categoria, patron por atributo y licencia por imagen."""
    with ruta_json.open("rb") as f:
        categorias = list(ijson.items(f, "categories.item"))
    with ruta_json.open("rb") as f:
        atributos = list(ijson.items(f, "attributes.item"))
    with ruta_json.open("rb") as f:
        licencias = {im["id"]: im["license"] for im in ijson.items(f, "images.item")}

    prendas = [c["name"] for c in categorias if c["supercategory"] not in _PARTES]
    patrones = [a["name"] for a in atributos if a["supercategory"] in mapeo.SUPERGRUPOS_DE_PATRON]
    problemas = mapeo.comprobar_ontologia(prendas, patrones)
    if problemas:
        raise SystemExit("La ontologia no coincide con el mapeo:\n" + "\n".join(problemas))

    tipo = {
        c["id"]: mapeo.TIPO_DESDE_FASHIONPEDIA[c["name"]]
        for c in categorias
        if c["name"] in mapeo.TIPO_DESDE_FASHIONPEDIA
    }
    nombre_atributo = {a["id"]: a["name"] for a in atributos}
    return tipo, nombre_atributo, licencias


_PARTES = {"garment parts", "closures", "decorations"}


def _seleccionar(ruta_json: Path, tipo_de: dict, atributo: dict, particion_de) -> dict[int, tuple]:
    """Pasada 1, sin mascaras: que anotaciones entran y con que etiquetas."""
    candidatas: dict[tuple[str, str], list] = collections.defaultdict(list)
    with ruta_json.open("rb") as f:
        for a in ijson.items(f, "annotations.item", use_float=True):
            tipo = tipo_de.get(a["category_id"])
            if tipo is None or a["iscrowd"]:
                continue
            _, _, w, h = a["bbox"]
            if min(w, h) < LADO_MINIMO:
                continue
            patron = mapeo.patron_de_atributos([atributo[i] for i in a["attribute_ids"]])
            particion = particion_de(a["image_id"])
            candidatas[(particion, tipo)].append((a["id"], tipo, patron, particion))

    rng = random.Random(SEMILLA)
    elegidas = {}
    for (particion, _), lista in sorted(candidatas.items()):
        rng.shuffle(lista)
        if particion in TOPE:
            # Los estampados son escasos: entran primero, y lo liso rellena.
            lista.sort(key=lambda x: x[2] in (None, "LISO"))
            lista = lista[: TOPE[particion]]
        elegidas.update({x[0]: x[1:] for x in lista})
    return elegidas


def _recortar(imagen: Image.Image, segmentacion, bbox) -> Image.Image:
    ancho, alto = imagen.size
    if isinstance(segmentacion, list):
        rles = mascara_coco.frPyObjects(segmentacion, alto, ancho)
        rle = mascara_coco.merge(rles)
    elif isinstance(segmentacion["counts"], list):
        rle = mascara_coco.frPyObjects(segmentacion, alto, ancho)
    else:
        rle = segmentacion
    m = mascara_coco.decode(rle).astype(bool)

    x, y, w, h = bbox
    margen = MARGEN * max(w, h)
    x0, y0 = int(max(0, x - margen)), int(max(0, y - margen))
    x1, y1 = int(min(ancho, x + w + margen)), int(min(alto, y + h + margen))
    rgb = np.asarray(imagen)[y0:y1, x0:x1].copy()
    rgb[~m[y0:y1, x0:x1]] = 255
    return _reducir(Image.fromarray(rgb))


def _reducir(im: Image.Image) -> Image.Image:
    escala = LADO / max(im.size)
    if escala < 1:
        im = im.resize((round(im.width * escala), round(im.height * escala)), Image.Resampling.LANCZOS)
    return im


def fashionpedia(rutas: configuracion.Rutas, carpeta: Path) -> list[dict]:
    filas = []
    fuentes = [
        ("instances_attributes_train2020.json", "train"),
        ("instances_attributes_val2020.json", "test"),
    ]
    for anotaciones, base in fuentes:
        ruta_json = rutas.fashionpedia / anotaciones
        tipo_de, atributo, licencias = _ontologia(ruta_json)
        nombre_licencia = {
            l["id"]: l["name"]
            for l in json.loads(_extraer_licencias(ruta_json))  # noqa: E741
        }

        if base == "train":
            ids = sorted(licencias)
            random.Random(SEMILLA).shuffle(ids)
            en_val = set(ids[: round(FRACCION_VAL * len(ids))])

            def particion_de(i, en_val=en_val):
                return "val" if i in en_val else "train"
        else:

            def particion_de(_):
                return "test"

        elegidas = _seleccionar(ruta_json, tipo_de, atributo, particion_de)
        print(f"{anotaciones}: {len(elegidas)} recortes elegidos", flush=True)

        carpeta_imagenes = rutas.fashionpedia / ("train" if base == "train" else "test")
        with ruta_json.open("rb") as f:
            nombres = {im["id"]: im["file_name"] for im in ijson.items(f, "images.item")}

        abierta: tuple[int, Image.Image] | None = None
        with ruta_json.open("rb") as f:
            for a in ijson.items(f, "annotations.item", use_float=True):
                if a["id"] not in elegidas:
                    continue
                tipo, patron, particion = elegidas[a["id"]]
                if abierta is None or abierta[0] != a["image_id"]:
                    ruta = carpeta_imagenes / nombres[a["image_id"]]
                    abierta = (a["image_id"], Image.open(ruta).convert("RGB"))
                archivo = f"fp_{a['id']}.jpg"
                _recortar(abierta[1], a["segmentation"], a["bbox"]).save(carpeta / archivo, quality=90)
                filas.append(
                    {
                        "archivo": archivo,
                        "fuente": "fashionpedia",
                        "particion": particion,
                        "tipo": tipo,
                        "patron": patron or "",
                        "licencia": nombre_licencia[licencias[a["image_id"]]],
                        "origen": nombres[a["image_id"]],
                    }
                )
                if len(filas) % 5000 == 0:
                    print(f"  {len(filas)} recortes", flush=True)
    return filas


def _extraer_licencias(ruta_json: Path) -> str:
    with ruta_json.open("rb") as f:
        return json.dumps(list(ijson.items(f, "licenses.item")))


# --------------------------------------------------------------------------- #
# Clothing dataset de Grigorev
# --------------------------------------------------------------------------- #


def grigorev(rutas: configuracion.Rutas, carpeta: Path) -> list[dict]:
    with (rutas.grigorev / "images.csv").open(newline="", encoding="utf-8") as f:
        registros = [r for r in csv.DictReader(f) if r["label"] in mapeo.TIPO_DESDE_GRIGOREV]
    personas = sorted({r["sender_id"] for r in registros})
    random.Random(SEMILLA).shuffle(personas)
    corte_val, corte_test = round(0.8 * len(personas)), round(0.9 * len(personas))
    particion = {
        p: "train" if i < corte_val else "val" if i < corte_test else "test"
        for i, p in enumerate(personas)
    }
    filas = []
    for r in registros:
        ruta = rutas.grigorev / "images" / f"{r['image']}.jpg"
        if not ruta.exists():
            continue
        archivo = f"cg_{r['image']}.jpg"
        _reducir(Image.open(ruta).convert("RGB")).save(carpeta / archivo, quality=90)
        filas.append(
            {
                "archivo": archivo,
                "fuente": "grigorev",
                "particion": particion[r["sender_id"]],
                "tipo": mapeo.TIPO_DESDE_GRIGOREV[r["label"]],
                "patron": "",
                "licencia": "CC0 1.0",
                "origen": r["image"],
            }
        )
    return filas


def principal() -> int:
    rutas = configuracion.cargar()
    carpeta = rutas.dataset / "imagenes"
    carpeta.mkdir(parents=True, exist_ok=True)

    filas = grigorev(rutas, carpeta)
    print(f"Grigorev: {len(filas)} imagenes", flush=True)
    filas += fashionpedia(rutas, carpeta)

    with (rutas.dataset / "manifiesto.csv").open("w", newline="", encoding="utf-8") as f:
        escritor = csv.DictWriter(f, fieldnames=list(filas[0]))
        escritor.writeheader()
        escritor.writerows(filas)

    resumen = collections.Counter((f["particion"], f["tipo"]) for f in filas)
    patrones = collections.Counter((f["particion"], f["patron"] or "-") for f in filas)
    licencias = collections.Counter(f["licencia"] for f in filas)
    informe = {
        "recortes": len(filas),
        "por_tipo": {f"{p}/{t}": n for (p, t), n in sorted(resumen.items())},
        "por_patron": {f"{p}/{t}": n for (p, t), n in sorted(patrones.items())},
        "licencias": dict(licencias.most_common()),
    }
    (rutas.dataset / "resumen.json").write_text(json.dumps(informe, indent=2), encoding="utf-8")
    print(json.dumps(informe, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(principal())
