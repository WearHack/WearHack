"""Reglas duras del outfit.

Son filtros: un outfit que las incumple no se puntua, se descarta. No son
preferencias que el costo pueda compensar.
"""

from collections.abc import Iterable

from app.motor.modelos import Clima, Outfit, Patron, Prenda, Slot, Textura

MAX_PRENDAS_NO_LISAS = 1
TEXTURAS_DE_ABRIGO = frozenset({Textura.PUNTO, Textura.ACOLCHADO})


def es_no_lisa(prenda: Prenda) -> bool:
    return prenda.patron != Patron.LISO


def respeta_maximo_no_lisas(prendas: Iterable[Prenda]) -> bool:
    """Como mucho una prenda con patron. Mas de una estampa pelea consigo misma."""
    return sum(es_no_lisa(p) for p in prendas) <= MAX_PRENDAS_NO_LISAS


def tiene_capa_para_frio(prendas: Iterable[Prenda]) -> bool:
    """Un EXTERIOR, o un TORSO_SUPERIOR de punto o acolchado."""
    return any(
        p.slot == Slot.EXTERIOR
        or (p.slot == Slot.TORSO_SUPERIOR and p.textura in TEXTURAS_DE_ABRIGO)
        for p in prendas
    )


def cumple_reglas_duras(outfit: Outfit, clima: Clima | None = None) -> bool:
    """`clima` es None cuando no se conoce: sin clima no se exige capa."""
    if not respeta_maximo_no_lisas(outfit):
        return False
    return clima != Clima.FRIO or tiene_capa_para_frio(outfit)
