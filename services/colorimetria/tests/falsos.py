"""Dobles para las pruebas: un artefacto sintetico, un segmentador sin MediaPipe
y una coleccion de Mongo en memoria. Ningun rostro real entra en el repositorio.
"""

import hashlib
import io
from dataclasses import asdict

import numpy as np

from app.extraccion.segmentacion import ParametrosSegmentacion, Regiones, SinRostro

MODELOS = {
    "face_landmarker.task": b"landmarker de prueba",
    "selfie_multiclass_256x256.tflite": b"segmentador de prueba",
}

# Colores sRGB de la imagen sintetica: piel calida y cabello muy oscuro, asi
# que el contraste es alto y la estacion esperada es OTONO.
PIEL = (205, 150, 115)
CABELLO = (45, 30, 20)
OJOS = (90, 60, 40)


def escribir_modelos(carpeta) -> None:
    for nombre, contenido in MODELOS.items():
        (carpeta / nombre).write_bytes(contenido)


def artefacto(version: str = "prueba-v1", **cambios) -> dict:
    """Un artefacto con la misma forma que el de `calibracion/`, con centroides de juguete."""
    segmentacion = asdict(ParametrosSegmentacion())
    segmentacion["modelos"] = {n: hashlib.sha256(c).hexdigest() for n, c in MODELOS.items()}
    datos = {
        "version": version,
        "estandarizacion": {
            "media": {"piel_calidez": 0.0, "contraste": 30.0},
            "desviacion": {"piel_calidez": 5.0, "contraste": 10.0},
        },
        "capas": {
            "subtono": {
                "variables": ["piel_calidez"],
                "centroides": {"CALIDO": [1.0], "FRIO": [-1.0]},
            },
            "contraste": {
                "variables": ["contraste"],
                "centroides": {"ALTO": [1.0], "BAJO": [-1.0]},
            },
        },
        "muestreo": {
            "piel_y_cabello": "mediana_p0_100",
            "ojos": "mediana_p20_80",
            "pixeles_minimos": {"piel": 50, "cabello": 50, "ojos": 4},
        },
        "segmentacion": segmentacion,
        "experimental": "Solo pruebas",
    }
    datos.update(cambios)
    return datos


class SegmentadorFalso:
    """Devuelve regiones fijas sobre una imagen sintetica, sin mirar la entrada."""

    creados = 0

    def __init__(
        self,
        ruta_landmarker,
        ruta_segmentador,
        parametros=None,
        *,
        sin_rostro=False,
        sin_piel=False,
        sin_cabello=False,
    ) -> None:
        type(self).creados += 1
        self.parametros = parametros
        self.sin_rostro = sin_rostro
        self.sin_piel = sin_piel
        self.sin_cabello = sin_cabello
        self.cerrado = False

    def __exit__(self, *_) -> None:
        self.cerrado = True

    def regiones(self, rgb: np.ndarray) -> Regiones:
        if self.sin_rostro:
            raise SinRostro()
        imagen = np.zeros((60, 40, 3), np.uint8)
        piel, cabello, ojos = (np.zeros((60, 40), bool) for _ in range(3))
        cabello[:20] = not self.sin_cabello
        piel[20:50] = not self.sin_piel
        ojos[50:54, 10:14] = True
        imagen[cabello] = CABELLO
        imagen[piel] = PIEL
        imagen[ojos] = OJOS
        return Regiones(rgb=imagen, piel=piel, cabello=cabello, ojos=ojos, ancho_rostro=30.0)


def png(ancho: int = 8, alto: int = 8, icc: bytes | None = None, formato: str = "PNG") -> bytes:
    from PIL import Image

    salida = io.BytesIO()
    extra = {"icc_profile": icc} if icc else {}
    Image.new("RGB", (ancho, alto), (120, 90, 70)).save(salida, format=formato, **extra)
    return salida.getvalue()


class ColeccionFalsa:
    """Lo minimo de una coleccion de pymongo que usa `RepositorioCentroides`."""

    def __init__(self) -> None:
        self.documentos: dict[str, dict] = {}
        self.falla = False

    def _coincide(self, documento: dict, filtro: dict) -> bool:
        for clave, valor in filtro.items():
            if isinstance(valor, dict) and "$ne" in valor:
                if documento.get(clave) == valor["$ne"]:
                    return False
            elif documento.get(clave) != valor:
                return False
        return True

    def _buscar(self, filtro: dict) -> list[dict]:
        if self.falla:
            raise ConnectionError("Mongo no responde")
        return [d for d in self.documentos.values() if self._coincide(d, filtro)]

    def find_one(self, filtro: dict, proyeccion: dict | None = None) -> dict | None:
        encontrados = self._buscar(filtro)
        return dict(encontrados[0]) if encontrados else None

    def find(self, filtro: dict, proyeccion: dict | None = None):
        encontrados = self._buscar(filtro)

        class Cursor(list):
            def sort(self, clave, sentido):
                return sorted(self, key=lambda d: d[clave], reverse=sentido < 0)

        return Cursor(dict(d) for d in encontrados)

    def insert_one(self, documento: dict) -> None:
        self.documentos[documento["_id"]] = dict(documento)

    def update_many(self, filtro: dict, cambio: dict) -> None:
        for d in self._buscar(filtro):
            d.update(cambio["$set"])

    def update_one(self, filtro: dict, cambio: dict) -> None:
        encontrados = self._buscar(filtro)
        if encontrados:
            encontrados[0].update(cambio["$set"])
