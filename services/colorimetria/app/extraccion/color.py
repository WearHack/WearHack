"""Conversiones de color: sRGB a Lab D65 y a HSV.

Nivel 0 de la normalizacion (respuestas A.9): sRGB se lineariza antes de pasar
a XYZ y a Lab. Cualquier correccion de luz va en RGB lineal, nunca en sRGB.
"""

import numpy as np

# sRGB lineal -> XYZ, iluminante D65 (IEC 61966-2-1).
_RGB_A_XYZ = np.array(
    [
        [0.4124564, 0.3575761, 0.1804375],
        [0.2126729, 0.7151522, 0.0721750],
        [0.0193339, 0.1191920, 0.9503041],
    ]
)
_BLANCO_D65 = np.array([0.95047, 1.0, 1.08883])


def srgb_a_lineal(rgb: np.ndarray) -> np.ndarray:
    """sRGB en [0, 255] (uint8 o float) a RGB lineal en [0, 1]."""
    c = np.asarray(rgb, dtype=np.float64) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lineal_a_srgb(lineal: np.ndarray) -> np.ndarray:
    """RGB lineal en [0, 1] a sRGB en [0, 255], sin redondear."""
    c = np.clip(lineal, 0.0, 1.0)
    return 255.0 * np.where(c <= 0.0031308, 12.92 * c, 1.055 * c ** (1 / 2.4) - 0.055)


def srgb_a_lab(rgb: np.ndarray) -> np.ndarray:
    """sRGB (..., 3) a CIE Lab D65 (..., 3)."""
    xyz = srgb_a_lineal(rgb) @ _RGB_A_XYZ.T / _BLANCO_D65
    delta = 6 / 29
    f = np.where(xyz > delta**3, np.cbrt(xyz), xyz / (3 * delta**2) + 4 / 29)
    luz = 116 * f[..., 1] - 16
    a = 500 * (f[..., 0] - f[..., 1])
    b = 200 * (f[..., 1] - f[..., 2])
    return np.stack([luz, a, b], axis=-1)


def srgb_a_hsv(rgb: np.ndarray) -> np.ndarray:
    """sRGB (..., 3) a HSV con H en grados [0, 360) y S, V en [0, 1]."""
    c = np.asarray(rgb, dtype=np.float64) / 255.0
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    v = c.max(axis=-1)
    rango = v - c.min(axis=-1)
    s = np.where(v > 0, rango / np.where(v > 0, v, 1), 0.0)
    seguro = np.where(rango > 0, rango, 1)
    h = np.select(
        [rango == 0, v == r, v == g],
        [0.0, ((g - b) / seguro) % 6, (b - r) / seguro + 2],
        default=(r - g) / seguro + 4,
    )
    return np.stack([60.0 * h % 360, s, v], axis=-1)
