"""Paso 1: descarga las fuentes del clasificador de prendas (issue #69).

    python tools/entrenamiento/prendas/descargar_fuentes.py

- Fashionpedia (base): imagenes train2020 y val_test2020, y anotaciones con
  atributos. Unos 4,1 GB.
- Clothing dataset de Alexey Grigorev (CC0): clon de git fijado a un commit.

Open Images V7 no se baja aqui: solo entra si una clase queda corta tras
construir el dataset (ver el README). DeepFashion2 y el ecosistema YOLO de
Ultralytics estan prohibidos (respuestas C.17).

Reanuda descargas a medias y no vuelve a bajar lo que ya esta. Escribe
`fuentes.json` con tamano y SHA-256 de cada archivo, que va a la procedencia.
Solo libreria estandar.
"""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import urllib.request
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import configuracion  # noqa: E402

_S3 = "https://s3.amazonaws.com/ifashionist-dataset"
FASHIONPEDIA = {
    "train2020.zip": f"{_S3}/images/train2020.zip",
    "val_test2020.zip": f"{_S3}/images/val_test2020.zip",
    "instances_attributes_train2020.json": f"{_S3}/annotations/instances_attributes_train2020.json",
    "instances_attributes_val2020.json": f"{_S3}/annotations/instances_attributes_val2020.json",
}
GRIGOREV = "https://github.com/alexeygrigorev/clothing-dataset.git"


def sha256(ruta: Path) -> str:
    h = hashlib.sha256()
    with ruta.open("rb") as f:
        for bloque in iter(lambda: f.read(1 << 20), b""):
            h.update(bloque)
    return h.hexdigest()


def descargar(url: str, destino: Path) -> None:
    peticion = urllib.request.Request(url, method="HEAD")
    with urllib.request.urlopen(peticion) as r:
        total = int(r.headers["Content-Length"])
    if destino.exists() and destino.stat().st_size == total:
        print(f"Ya esta: {destino.name}")
        return
    parcial = destino.with_suffix(destino.suffix + ".part")
    desde = parcial.stat().st_size if parcial.exists() else 0
    peticion = urllib.request.Request(url, headers={"Range": f"bytes={desde}-"} if desde else {})
    with urllib.request.urlopen(peticion) as r, parcial.open("ab" if desde else "wb") as f:
        if desde and r.status != 206:
            raise RuntimeError(f"{url} no admite reanudar; borra {parcial} y repite")
        hecho, aviso = desde, 0
        for bloque in iter(lambda: r.read(1 << 20), b""):
            f.write(bloque)
            hecho += len(bloque)
            if hecho - aviso >= 250 << 20:
                print(f"  {destino.name}: {hecho >> 20} / {total >> 20} MB", flush=True)
                aviso = hecho
    if parcial.stat().st_size != total:
        raise RuntimeError(f"{destino.name}: tamano {parcial.stat().st_size}, esperado {total}")
    parcial.replace(destino)
    print(f"Descargado: {destino.name}")


def extraer(zip_: Path, carpeta: Path) -> None:
    marca = carpeta / f".extraido-{zip_.name}"
    if marca.exists():
        return
    with zipfile.ZipFile(zip_) as z:
        for nombre in z.namelist():
            destino = (carpeta / nombre).resolve()
            if not destino.is_relative_to(carpeta.resolve()):
                raise RuntimeError(f"{zip_.name}: ruta fuera de la carpeta: {nombre}")
        z.extractall(carpeta)
    marca.touch()
    print(f"Extraido: {zip_.name}")


def principal() -> int:
    rutas = configuracion.cargar()
    rutas.fashionpedia.mkdir(parents=True, exist_ok=True)
    fuentes: dict[str, dict] = {"fashionpedia": {}, "grigorev": {}}

    for nombre, url in FASHIONPEDIA.items():
        destino = rutas.fashionpedia / nombre
        descargar(url, destino)
        fuentes["fashionpedia"][nombre] = {
            "url": url,
            "bytes": destino.stat().st_size,
            "sha256": sha256(destino),
        }
        if nombre.endswith(".zip"):
            extraer(destino, rutas.fashionpedia)

    if not rutas.grigorev.exists():
        subprocess.run(["git", "clone", "--depth", "1", GRIGOREV, str(rutas.grigorev)], check=True)
    commit = subprocess.run(
        ["git", "-C", str(rutas.grigorev), "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    fuentes["grigorev"] = {"url": GRIGOREV, "commit": commit}

    (rutas.datos / "fuentes.json").write_text(json.dumps(fuentes, indent=2), encoding="utf-8")
    print(json.dumps(fuentes, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(principal())
