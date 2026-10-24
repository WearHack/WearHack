"""Compatibilidad de color por matiz, en LCh.

Dos colores combinan bien si su diferencia de matiz cae en una banda de armonia
(analoga, triadica o complementaria): ahi el costo es 0. Fuera de las bandas el
costo sube en lineal con la distancia a la banda mas cercana hasta llegar a 1.
Los neutros combinan con todo y cuestan 0 siempre.

Todos los umbrales viven en `ReglasColor` para poder ajustarlos sin tocar la
logica. Es una funcion pura: la misma sirve para el lote y para tiempo real.
"""

from dataclasses import dataclass

DENIM = "DENIM"


@dataclass(frozen=True)
class ColorLCh:
    """Un color en LCh (luminosidad, croma, matiz en grados)."""

    luz: float
    croma: float
    matiz: float


@dataclass(frozen=True)
class ReglasColor:
    # Bandas de armonia: (centro, semiancho) del delta de matiz, en grados.
    analoga_max: float = 30.0
    triadica_centro: float = 120.0
    triadica_semiancho: float = 15.0
    complementaria_centro: float = 180.0
    complementaria_semiancho: float = 20.0
    # Grados de distancia a la banda mas cercana a los que el costo llega a 1.
    # 37.5 es el hueco mas ancho entre bandas (de 30 a 105), asi que el peor
    # matiz posible cuesta exactamente 1.
    grados_para_costo_maximo: float = 37.5
    # Neutros.
    neutro_croma_max: float = 15.0
    neutro_oscuro_l_max: float = 35.0
    neutro_oscuro_croma_max: float = 30.0


def delta_matiz(h1: float, h2: float) -> float:
    """Diferencia de matiz en [0, 180], midiendo por el lado corto del circulo."""
    d = abs(h1 - h2) % 360.0
    return 360.0 - d if d > 180.0 else d


def es_neutro(color: ColorLCh, textura: str | None, reglas: ReglasColor = ReglasColor()) -> bool:
    if textura == DENIM:
        return True
    if color.croma < reglas.neutro_croma_max:
        return True
    return color.luz < reglas.neutro_oscuro_l_max and color.croma < reglas.neutro_oscuro_croma_max


def costo_color(
    a: ColorLCh,
    b: ColorLCh,
    textura_a: str | None = None,
    textura_b: str | None = None,
    reglas: ReglasColor = ReglasColor(),
) -> float:
    """Costo en [0, 1] de combinar `a` con `b`. 0 es compatible."""
    if es_neutro(a, textura_a, reglas) or es_neutro(b, textura_b, reglas):
        return 0.0

    d = delta_matiz(a.matiz, b.matiz)
    distancia = min(
        max(0.0, d - reglas.analoga_max),
        max(0.0, abs(d - reglas.triadica_centro) - reglas.triadica_semiancho),
        max(0.0, abs(d - reglas.complementaria_centro) - reglas.complementaria_semiancho),
    )
    return min(1.0, distancia / reglas.grados_para_costo_maximo)
