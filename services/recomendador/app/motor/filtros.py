"""Filtros duros de contexto: clima apto y dress code.

Se aplican prenda a prenda antes de combinar: lo que no sirve para el clima o el
evento no entra al escaneo. La coherencia entre prendas que si pasan (tenis con
blazer) no es cosa del filtro sino del costo de formalidad.
"""

from collections.abc import Iterable

from app.motor.modelos import Clima, Prenda, RangoFormalidad


def pasa_clima(prenda: Prenda, clima: Clima | None) -> bool:
    """Sin clima conocido, todo pasa."""
    return clima is None or clima in prenda.clima_apto


def pasa_dress_code(prenda: Prenda, rango_evento: RangoFormalidad | None) -> bool:
    """El rango de la prenda se cruza con el del evento; sin formalidad, siempre pasa."""
    if rango_evento is None or prenda.formalidad is None:
        return True
    minimo, maximo = prenda.formalidad
    return minimo <= rango_evento[1] and rango_evento[0] <= maximo


def filtrar_por_contexto(
    closet: Iterable[Prenda], clima: Clima | None, rango_evento: RangoFormalidad | None
) -> list[Prenda]:
    return [p for p in closet if pasa_clima(p, clima) and pasa_dress_code(p, rango_evento)]
