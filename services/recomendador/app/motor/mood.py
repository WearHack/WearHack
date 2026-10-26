"""Termino suave de mood.

`costo = w_mood * C_mood`, con `w_mood = 0.2`, y 0 cuando el usuario no pidio
mood. Cada mood mide una cosa distinta del outfit y devuelve un costo en [0, 1]
(menor es mejor):

- RELAJADO: formalidad normalizada dentro del rango del evento.
- ELEGANTE: lo contrario, `1 - formalidad normalizada`.
- ATREVIDO: proporcion de prendas neutras (favorece color y estampado).
- DISCRETO: croma promedio normalizado (favorece neutros y analogos).
"""

from dataclasses import dataclass
from enum import StrEnum
from statistics import mean

from app.motor.color import ReglasColor, es_neutro
from app.motor.modelos import Formalidad, Outfit, RangoFormalidad

W_MOOD = 0.2


class Mood(StrEnum):
    RELAJADO = "RELAJADO"
    ELEGANTE = "ELEGANTE"
    ATREVIDO = "ATREVIDO"
    DISCRETO = "DISCRETO"


@dataclass(frozen=True)
class ReglasMood:
    w_mood: float = W_MOOD
    # Croma al que una prenda cuenta como "todo croma". LCh rara vez pasa de ~100.
    croma_maximo: float = 100.0
    color: ReglasColor = ReglasColor()


RANGO_COMPLETO: RangoFormalidad = (Formalidad.DEPORTIVO, Formalidad.FORMAL)


def formalidad_normalizada(outfit: Outfit, rango_evento: RangoFormalidad = RANGO_COMPLETO) -> float:
    """Formalidad media del outfit, en [0, 1] dentro del rango del evento.

    Cada prenda aporta el punto medio de su rango; las que no tienen (accesorios
    neutros) no cuentan. Si el rango del evento es de un solo nivel no hay nada
    que discriminar y devuelve 0.5, para que RELAJADO y ELEGANTE cuesten igual.
    """
    niveles = [(p.formalidad[0] + p.formalidad[1]) / 2 for p in outfit if p.formalidad]
    minimo, maximo = rango_evento
    if not niveles or maximo == minimo:
        return 0.5
    return min(1.0, max(0.0, (mean(niveles) - minimo) / (maximo - minimo)))


def costo_mood(
    outfit: Outfit,
    mood: Mood | None,
    rango_evento: RangoFormalidad = RANGO_COMPLETO,
    reglas: ReglasMood = ReglasMood(),
) -> float:
    """C_mood en [0, 1]. Sin mood, 0."""
    if mood is None:
        return 0.0
    if mood == Mood.RELAJADO:
        return formalidad_normalizada(outfit, rango_evento)
    if mood == Mood.ELEGANTE:
        return 1.0 - formalidad_normalizada(outfit, rango_evento)

    con_color = [p for p in outfit if p.color is not None]
    if not con_color:
        return 0.0
    if mood == Mood.ATREVIDO:
        neutras = sum(es_neutro(p.color, p.textura, reglas.color) for p in con_color)
        return neutras / len(con_color)
    # DISCRETO
    return min(1.0, mean(p.color.croma for p in con_color) / reglas.croma_maximo)


def costo_mood_ponderado(
    outfit: Outfit,
    mood: Mood | None,
    rango_evento: RangoFormalidad = RANGO_COMPLETO,
    reglas: ReglasMood = ReglasMood(),
) -> float:
    """`w_mood * C_mood`: lo que el motor suma al costo del outfit."""
    if mood is None:
        return 0.0
    return reglas.w_mood * costo_mood(outfit, mood, rango_evento, reglas)
