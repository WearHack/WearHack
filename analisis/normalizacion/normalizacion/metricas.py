"""Las piezas numericas de las metricas: ΔE00, Spearman, ITA y calidad.

Sin dependencias fuera de numpy, para que el analisis corra con el mismo entorno
que la calibracion del servicio de Colorimetria.
"""

import math

import numpy as np


def delta_e_00(lab1, lab2) -> np.ndarray:
    """CIEDE2000 (Sharma, Wu y Dalal, 2005) entre (..., 3) y (..., 3)."""
    L1, a1, b1 = np.moveaxis(np.asarray(lab1, dtype=np.float64), -1, 0)
    L2, a2, b2 = np.moveaxis(np.asarray(lab2, dtype=np.float64), -1, 0)
    C1, C2 = np.hypot(a1, b1), np.hypot(a2, b2)
    C_med = (C1 + C2) / 2
    G = 0.5 * (1 - np.sqrt(C_med**7 / (C_med**7 + 25.0**7)))
    a1p, a2p = (1 + G) * a1, (1 + G) * a2
    C1p, C2p = np.hypot(a1p, b1), np.hypot(a2p, b2)
    h1p = np.degrees(np.arctan2(b1, a1p)) % 360
    h2p = np.degrees(np.arctan2(b2, a2p)) % 360

    dLp = L2 - L1
    dCp = C2p - C1p
    dhp = h2p - h1p
    dhp = np.where(dhp > 180, dhp - 360, np.where(dhp < -180, dhp + 360, dhp))
    dhp = np.where(C1p * C2p == 0, 0.0, dhp)
    dHp = 2 * np.sqrt(C1p * C2p) * np.sin(np.radians(dhp) / 2)

    Lp_med = (L1 + L2) / 2
    Cp_med = (C1p + C2p) / 2
    suma_h = h1p + h2p
    hp_med = np.where(
        C1p * C2p == 0,
        suma_h,
        np.where(
            np.abs(h1p - h2p) <= 180,
            suma_h / 2,
            np.where(suma_h < 360, (suma_h + 360) / 2, (suma_h - 360) / 2),
        ),
    )
    T = (
        1
        - 0.17 * np.cos(np.radians(hp_med - 30))
        + 0.24 * np.cos(np.radians(2 * hp_med))
        + 0.32 * np.cos(np.radians(3 * hp_med + 6))
        - 0.20 * np.cos(np.radians(4 * hp_med - 63))
    )
    d_theta = 30 * np.exp(-(((hp_med - 275) / 25) ** 2))
    R_C = 2 * np.sqrt(Cp_med**7 / (Cp_med**7 + 25.0**7))
    S_L = 1 + 0.015 * (Lp_med - 50) ** 2 / np.sqrt(20 + (Lp_med - 50) ** 2)
    S_C = 1 + 0.045 * Cp_med
    S_H = 1 + 0.015 * Cp_med * T
    R_T = -np.sin(np.radians(2 * d_theta)) * R_C
    return np.sqrt((dLp / S_L) ** 2 + (dCp / S_C) ** 2 + (dHp / S_H) ** 2 + R_T * (dCp / S_C) * (dHp / S_H))


def _rangos(x: np.ndarray) -> np.ndarray:
    """Rangos con empates promediados."""
    orden = np.argsort(x, kind="mergesort")
    rangos = np.empty(len(x))
    rangos[orden] = np.arange(1, len(x) + 1)
    for valor in np.unique(x):
        iguales = x == valor
        if iguales.sum() > 1:
            rangos[iguales] = rangos[iguales].mean()
    return rangos


def spearman(x, y) -> float:
    """Correlacion de Spearman (M4). NaN con menos de 3 pares o sin variacion."""
    x, y = np.asarray(x, dtype=float), np.asarray(y, dtype=float)
    ok = ~(np.isnan(x) | np.isnan(y))
    x, y = x[ok], y[ok]
    if len(x) < 3:
        return math.nan
    rx, ry = _rangos(x), _rangos(y)
    if rx.std() == 0 or ry.std() == 0:
        return math.nan
    return float(np.corrcoef(rx, ry)[0, 1])


def ita(L: float, b: float) -> float:
    """Angulo tipologico individual, en grados (Chardon et al., 1991)."""
    return math.degrees(math.atan2(L - 50, b))


def calidad(rgb: np.ndarray) -> dict[str, float]:
    """Los controles del cliente (`controles_calidad.dart`), sobre el recorte entero.

    Mismas definiciones: quemados = algun canal en 255; negros = los tres en 0;
    nitidez = varianza del laplaciano de 4 vecinos sobre la luminancia.
    """
    rgb = np.asarray(rgb)
    pixeles = rgb.shape[0] * rgb.shape[1]
    quemados = float((rgb == 255).any(axis=2).sum() * 100 / pixeles)
    negros = float((rgb == 0).all(axis=2).sum() * 100 / pixeles)
    r, g, b = (rgb[..., i].astype(np.int32) for i in range(3))
    luma = (299 * r + 587 * g + 114 * b) // 1000
    lap = luma[:-2, 1:-1] + luma[2:, 1:-1] + luma[1:-1, :-2] + luma[1:-1, 2:] - 4 * luma[1:-1, 1:-1]
    nitidez = float(lap.astype(np.float64).var()) if lap.size else 0.0
    return {"quemados_pct": quemados, "negros_pct": negros, "nitidez": nitidez}
