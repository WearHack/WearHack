"""Las tecnicas de normalizacion del protocolo (seccion 4).

Todas hacen lo mismo en dos pasos: **estimar** el color de la luz como un vector
RGB lineal y **corregir** el recorte con escalado de von Kries en RGB lineal,
nunca sobre valores con gamma (protocolo, seccion 2).

- T0: sin correccion. Supone luz neutra; es la linea base.
- T1: el blanco del ojo (esclerotica) como referencia de blanco.
- T2: los brillos especulares de piel y ojos como color de la luz. Es la
  aproximacion simple del modelo dicromatico (max-RGB acotado a los brillos);
  el ajuste del plano dicromatico completo queda para despues si T2 promete.
- REF: el parche gris de la tarjeta, en la foto completa. Solo en las fotos
  `R1`; es el mejor caso posible, no una opcion del producto.

T3 (modelo aprendido) y T4 (pantalla como flash) no entran en #66.
"""

import math

import numpy as np

from app.extraccion.color import lineal_a_srgb, srgb_a_lineal

NEUTRA = np.ones(3) / math.sqrt(3)
TECNICAS = ("T0", "T1", "T2", "REF")
# Por encima, un canal se considera recortado por saturacion (sRGB 254 o mas).
_RECORTADO = srgb_a_lineal(np.array([254.0]))[0]
_MINIMO_PIXELES = 20


def unitario(v: np.ndarray) -> np.ndarray:
    v = np.asarray(v, dtype=np.float64)
    n = np.linalg.norm(v)
    return v / n if n > 0 else NEUTRA


def angulo(a: np.ndarray, b: np.ndarray) -> float:
    """Angulo en grados entre dos colores de luz (la metrica M3)."""
    coseno = float(np.clip(np.dot(unitario(a), unitario(b)), -1.0, 1.0))
    return math.degrees(math.acos(coseno))


def _utiles(rgb: np.ndarray, mascara: np.ndarray) -> np.ndarray:
    """Pixeles lineales (n, 3) de la mascara, sin recortados ni negros."""
    lineal = srgb_a_lineal(np.asarray(rgb)[np.asarray(mascara, dtype=bool)])
    ok = (lineal.max(axis=1) < _RECORTADO) & (lineal.sum(axis=1) > 0.01)
    return lineal[ok]


def estimar_t0(*_) -> np.ndarray:
    return NEUTRA


def estimar_t1(rgb: np.ndarray, esclerotica: np.ndarray | None) -> np.ndarray | None:
    """Mediana del blanco del ojo, sin sombras (parpado) ni brillos (reflejos).

    None si el ojo no se ve lo bastante: la toma cuenta como no corregible.
    """
    if esclerotica is None:
        return None
    pixeles = _utiles(rgb, esclerotica)
    if len(pixeles) < _MINIMO_PIXELES:
        return None
    luz = pixeles.sum(axis=1)
    bajo, alto = np.percentile(luz, [25, 90])
    medio = pixeles[(luz >= bajo) & (luz <= alto)]
    return unitario(np.median(medio, axis=0)) if len(medio) else None


def estimar_t2(
    rgb: np.ndarray, piel: np.ndarray, ojos: np.ndarray, fraccion: float = 0.01
) -> np.ndarray | None:
    """Color de los pixeles mas brillantes de piel y ojos, sin los recortados.

    En un brillo especular domina el color de la luz sobre el de la piel (modelo
    dicromatico): por eso solo se mira la fraccion mas brillante.
    """
    pixeles = _utiles(rgb, np.asarray(piel, bool) | np.asarray(ojos, bool))
    if len(pixeles) < _MINIMO_PIXELES:
        return None
    luz = pixeles.sum(axis=1)
    corte = np.quantile(luz, 1 - fraccion)
    brillos = pixeles[luz >= corte]
    return unitario(np.median(brillos, axis=0)) if len(brillos) else None


def estimar_ref(gris_lineal: np.ndarray | None) -> np.ndarray | None:
    """El parche gris medido en la foto completa (ver `tarjeta.medir`)."""
    return None if gris_lineal is None else unitario(gris_lineal)


def corregir(rgb: np.ndarray, luz: np.ndarray) -> np.ndarray:
    """Von Kries en RGB lineal: la luz estimada pasa a ser neutra.

    Las ganancias conservan la media de los canales, asi una luz neutra no
    cambia nada y la luminosidad global apenas se mueve. Devuelve sRGB en
    [0, 255] como float, sin redondear, para no perder precision al medir.
    """
    luz = np.asarray(luz, dtype=np.float64)
    ganancias = luz.mean() / np.maximum(luz, 1e-6)
    return lineal_a_srgb(srgb_a_lineal(rgb) * ganancias)
