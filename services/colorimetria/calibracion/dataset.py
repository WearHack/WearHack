"""Deep Armocromia tal como lo entregan los autores.

    <raiz>/{train,test}/{autunno,estate,inverno,primavera}/<subtipo>/<id>.png

Las estaciones vienen en italiano; aqui se traducen a las del dominio.
"""

import hashlib
from dataclasses import dataclass
from pathlib import Path

ESTACION_DESDE_ITALIANO = {
    "primavera": "PRIMAVERA",
    "estate": "VERANO",
    "autunno": "OTONO",
    "inverno": "INVIERNO",
}
PARTICIONES = ("train", "test")


@dataclass(frozen=True)
class Imagen:
    ruta: Path
    particion: str
    estacion: str
    subtipo: str

    @property
    def id(self) -> str:
        """Ruta relativa a la raiz, con /, estable entre maquinas."""
        return "/".join(self.ruta.parts[-4:])


def listar(raiz: Path) -> list[Imagen]:
    imagenes = []
    for particion in PARTICIONES:
        for italiano, estacion in ESTACION_DESDE_ITALIANO.items():
            for ruta in sorted((raiz / particion / italiano).glob("*/*.png")):
                imagenes.append(Imagen(ruta, particion, estacion, ruta.parent.name.upper()))
    if not imagenes:
        raise FileNotFoundError(f"No hay imagenes con la estructura esperada en {raiz}")
    return imagenes


def sha256(ruta: Path) -> str:
    h = hashlib.sha256()
    with ruta.open("rb") as f:
        for bloque in iter(lambda: f.read(1 << 20), b""):
            h.update(bloque)
    return h.hexdigest()


def hash_del_manifiesto(filas: list[tuple[str, str]]) -> str:
    """Un solo hash para el dataset: SHA-256 de las lineas `id  sha256` ordenadas."""
    texto = "".join(f"{i}  {h}\n" for i, h in sorted(filas))
    return hashlib.sha256(texto.encode()).hexdigest()
