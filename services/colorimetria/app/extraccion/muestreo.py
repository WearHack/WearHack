"""Muestreo de una region: el color representativo de piel, cabello u ojos.

Recorte por percentil de L* y luego mediana (respuestas A.7 y A.10): el
percentil quita sombras y brillos sin un umbral fijo que dependa de la luz.
Sin k-means.

La media sin recorte se conserva como variante porque es lo que usa la tesis de
Dinh, y la diferencia entre las dos hay que medirla, no suponerla (A.5).
"""

from dataclasses import dataclass

import numpy as np

from app.extraccion.color import srgb_a_hsv, srgb_a_lab

CANALES = ("L", "a", "b", "S", "V")


@dataclass(frozen=True)
class Variante:
    """Como se resume una region. Los percentiles son de L* dentro de la region."""

    estadistico: str  # "mediana" o "media"
    percentil_bajo: float = 0.0
    percentil_alto: float = 100.0

    @property
    def nombre(self) -> str:
        return f"{self.estadistico}_p{self.percentil_bajo:g}_{self.percentil_alto:g}"

    @classmethod
    def desde_nombre(cls, nombre: str) -> "Variante":
        """La inversa de `nombre`: 'mediana_p20_80' -> Variante('mediana', 20, 80)."""
        estadistico, bajo, alto = nombre.split("_")
        if estadistico not in ("mediana", "media") or not bajo.startswith("p"):
            raise ValueError(f"Variante de muestreo desconocida: {nombre!r}")
        return cls(estadistico, float(bajo[1:]), float(alto))


@dataclass(frozen=True)
class Muestra:
    """Color representativo de una region, en Lab D65 y en S y V de HSV.

    El matiz de HSV no se resume: es circular y su mediana no tiene sentido
    cerca de 0/360, que es justo donde caen los cabellos rojizos. El matiz sale
    de a y b.
    """

    L: float
    a: float
    b: float
    S: float
    V: float
    pixeles: int

    @property
    def croma(self) -> float:
        return float(np.hypot(self.a, self.b))

    @property
    def matiz(self) -> float:
        """Angulo de matiz h_ab en grados [0, 360)."""
        return float(np.degrees(np.arctan2(self.b, self.a)) % 360)


def pixeles_de_region(rgb: np.ndarray, mascara: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Lab y HSV (n, 3) de los pixeles de la mascara."""
    seleccion = np.asarray(rgb)[np.asarray(mascara, dtype=bool)]
    return srgb_a_lab(seleccion), srgb_a_hsv(seleccion)


def muestrear(
    lab: np.ndarray, hsv: np.ndarray, variante: Variante, minimo_pixeles: int
) -> Muestra | None:
    """Resume los pixeles de una region. None si quedan menos del minimo.

    El minimo se comprueba despues del recorte: una region que solo pasa antes
    de recortar es demasiado pequena para fiarse de ella.
    """
    if len(lab) == 0:
        return None
    luz = lab[:, 0]
    bajo, alto = np.percentile(luz, [variante.percentil_bajo, variante.percentil_alto])
    dentro = (luz >= bajo) & (luz <= alto)
    if int(dentro.sum()) < minimo_pixeles:
        return None
    resumir = np.median if variante.estadistico == "mediana" else np.mean
    L, a, b = (float(v) for v in resumir(lab[dentro], axis=0))
    S, V = (float(v) for v in resumir(hsv[dentro][:, 1:], axis=0))
    return Muestra(L=L, a=a, b=b, S=S, V=V, pixeles=int(dentro.sum()))


def muestrear_regiones(
    rgb: np.ndarray,
    mascaras: dict[str, np.ndarray],
    variantes: dict[str, Variante],
    minimos: dict[str, int],
) -> dict[str, Muestra | None]:
    """Una muestra por region, con la variante y el minimo de cada una.

    Es lo que hace la calibracion en dos pasos (extraer con minimo 1 y descartar
    luego por debajo del minimo), en uno: `muestrear` comprueba el minimo
    despues del recorte, igual que alli.
    """
    muestras = {}
    for region, mascara in mascaras.items():
        lab, hsv = pixeles_de_region(rgb, mascara)
        muestras[region] = muestrear(lab, hsv, variantes[region], minimos[region])
    return muestras
