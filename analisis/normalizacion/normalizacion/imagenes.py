"""Leer fotos como sRGB, con la gestion de color del nivel 0.

El recorte ya llega en sRGB (lo convierte la app). La foto completa no: el
iPhone suele capturar en Display P3, y asumir sRGB desplaza a* y b*. Aqui se
endereza segun el EXIF y se convierte a sRGB con su perfil ICC.
"""

import io
from pathlib import Path

import numpy as np


def leer_srgb(ruta: Path) -> np.ndarray:
    """(alto, ancho, 3) uint8 en sRGB, ya orientada."""
    from PIL import Image, ImageCms, ImageOps

    with Image.open(ruta) as original:
        imagen = ImageOps.exif_transpose(original)
        icc = original.info.get("icc_profile")
        imagen = imagen.convert("RGB")
        if icc:
            origen = ImageCms.ImageCmsProfile(io.BytesIO(icc))
            imagen = ImageCms.profileToProfile(imagen, origen, ImageCms.createProfile("sRGB"))
        return np.asarray(imagen, dtype=np.uint8)
