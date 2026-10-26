"""Componentes del costo de un outfit (D.22). Menor es mejor.

    costo = w_color*C_color + w_paleta*C_paleta + w_form*C_form + w_tex*C_tex
            + w_mood*C_mood

Cada componente esta en [0, 1]. Los de pares (color, formalidad, textura) son el
promedio sobre los pares de prendas que tienen ese atributo; el de paleta es el
promedio sobre las prendas que enmarcan la cara. Sin datos, el componente
vale 0: no hay nada que penalizar.
"""

from collections.abc import Callable, Iterable, Mapping
from dataclasses import dataclass, field
from enum import StrEnum
from itertools import combinations
from statistics import mean
from typing import TypeVar

from app.motor.color import ReglasColor, costo_color, es_neutro
from app.motor.modelos import Outfit, Prenda, RangoFormalidad, Slot, Textura
from app.motor.mood import RANGO_COMPLETO, Mood, ReglasMood, costo_mood

T = TypeVar("T")

# C_paleta solo mira lo que queda junto a la cara.
SLOTS_PALETA = frozenset({Slot.TORSO_SUPERIOR, Slot.ACCESORIO_CUELLO, Slot.EXTERIOR})


@dataclass(frozen=True)
class Pesos:
    color: float = 0.35
    paleta: float = 0.25
    formalidad: float = 0.25
    textura: float = 0.15


PESOS_INICIALES = Pesos()


class Estacion(StrEnum):
    PRIMAVERA = "PRIMAVERA"
    VERANO = "VERANO"
    OTONO = "OTONO"
    INVIERNO = "INVIERNO"


@dataclass(frozen=True)
class PerfilColor:
    """Probabilidades del clasificador de colorimetria por estacion."""

    probabilidades: Mapping[Estacion, float]

    def _p(self, *estaciones: Estacion) -> float:
        return sum(self.probabilidades.get(e, 0.0) for e in estaciones)

    @property
    def p_calido(self) -> float:
        return self._p(Estacion.PRIMAVERA, Estacion.OTONO)

    @property
    def p_frio(self) -> float:
        return self._p(Estacion.VERANO, Estacion.INVIERNO)

    @property
    def p_contraste_bajo(self) -> float:
        return self._p(Estacion.PRIMAVERA, Estacion.VERANO)


@dataclass(frozen=True)
class ReglasPaleta:
    """La spec deja la curva de croma y el corte de matiz sin definir (D.22).

    Estos valores son un punto de partida, no una decision: se ajustan aqui.
    """

    # Matices LCh en [desde, hasta) cuentan como calidos: rojos, naranjas,
    # amarillos. El resto (verdes, azules, morados, rosas) como frios.
    matiz_calido_desde: float = 20.0
    matiz_calido_hasta: float = 115.0
    # Por encima de `croma_alto` el contraste bajo empieza a penalizar, en lineal
    # hasta 1 en `croma_maximo`.
    croma_alto: float = 60.0
    croma_maximo: float = 100.0
    peso_temperatura: float = 0.5
    peso_croma: float = 0.5


@dataclass(frozen=True)
class TablaTexturas:
    """Coocurrencia de texturas aprendida de lo que el usuario elige (D.26).

    `q = (pos - neg) / (pos + neg + 5)` y `C_tex = (1 - q) / 2`. Sin datos q es
    0, asi que todos los pares arrancan en 0.5.
    """

    positivos: Mapping[frozenset[Textura], int] = field(default_factory=dict)
    negativos: Mapping[frozenset[Textura], int] = field(default_factory=dict)

    def costo(self, a: Textura, b: Textura) -> float:
        par = frozenset({a, b})
        pos, neg = self.positivos.get(par, 0), self.negativos.get(par, 0)
        q = (pos - neg) / (pos + neg + 5)
        return (1 - q) / 2


def _promedio_pares(
    prendas: Iterable[Prenda], tiene: Callable[[Prenda], bool], costo: Callable[[T, T], float]
) -> float:
    validas = [p for p in prendas if tiene(p)]
    costos = [costo(a, b) for a, b in combinations(validas, 2)]
    return mean(costos) if costos else 0.0


def c_color(outfit: Outfit, reglas: ReglasColor = ReglasColor()) -> float:
    return _promedio_pares(
        outfit,
        lambda p: p.color is not None,
        lambda a, b: costo_color(a.color, b.color, a.textura, b.textura, reglas),
    )


def _distancia_formalidad(a: RangoFormalidad, b: RangoFormalidad) -> float:
    """0 si los rangos se cruzan; si no, los niveles que los separan entre 3."""
    hueco = max(a[0] - b[1], b[0] - a[1])
    return max(0, hueco) / 3


def c_formalidad(outfit: Outfit) -> float:
    return _promedio_pares(
        outfit,
        lambda p: p.formalidad is not None,
        lambda a, b: _distancia_formalidad(a.formalidad, b.formalidad),
    )


def c_textura(outfit: Outfit, tabla: TablaTexturas = TablaTexturas()) -> float:
    return _promedio_pares(
        outfit,
        lambda p: p.textura is not None,
        lambda a, b: tabla.costo(a.textura, b.textura),
    )


def es_calido(matiz: float, reglas: ReglasPaleta = ReglasPaleta()) -> bool:
    return reglas.matiz_calido_desde <= matiz % 360 < reglas.matiz_calido_hasta


def c_paleta_prenda(
    prenda: Prenda,
    perfil: PerfilColor,
    reglas: ReglasPaleta = ReglasPaleta(),
    reglas_color: ReglasColor = ReglasColor(),
) -> float:
    """Que tan mal le queda a la persona el color de una prenda junto a la cara."""
    if prenda.slot not in SLOTS_PALETA or prenda.color is None:
        return 0.0
    if es_neutro(prenda.color, prenda.textura, reglas_color):
        return 0.0
    calida = es_calido(prenda.color.matiz, reglas)
    temperatura = perfil.p_frio if calida else perfil.p_calido
    exceso = (prenda.color.croma - reglas.croma_alto) / (reglas.croma_maximo - reglas.croma_alto)
    croma = perfil.p_contraste_bajo * min(1.0, max(0.0, exceso))
    return reglas.peso_temperatura * temperatura + reglas.peso_croma * croma


def c_paleta(
    outfit: Outfit,
    perfil: PerfilColor | None,
    reglas: ReglasPaleta = ReglasPaleta(),
    reglas_color: ReglasColor = ReglasColor(),
) -> float:
    if perfil is None:
        return 0.0
    cerca_de_la_cara = [p for p in outfit if p.slot in SLOTS_PALETA and p.color is not None]
    if not cerca_de_la_cara:
        return 0.0
    return mean(c_paleta_prenda(p, perfil, reglas, reglas_color) for p in cerca_de_la_cara)


@dataclass(frozen=True)
class ReglasCosto:
    color: ReglasColor = ReglasColor()
    paleta: ReglasPaleta = ReglasPaleta()
    mood: ReglasMood = ReglasMood()
    texturas: TablaTexturas = TablaTexturas()


@dataclass(frozen=True)
class Componentes:
    """Los componentes por separado: el aprendizaje (D.26) los necesita asi."""

    color: float
    paleta: float
    formalidad: float
    textura: float
    mood: float

    def total(self, pesos: Pesos, w_mood: float) -> float:
        return (
            pesos.color * self.color
            + pesos.paleta * self.paleta
            + pesos.formalidad * self.formalidad
            + pesos.textura * self.textura
            + w_mood * self.mood
        )


def componentes(
    outfit: Outfit,
    perfil: PerfilColor | None = None,
    mood: Mood | None = None,
    rango_evento: RangoFormalidad | None = None,
    reglas: ReglasCosto = ReglasCosto(),
) -> Componentes:
    return Componentes(
        color=c_color(outfit, reglas.color),
        paleta=c_paleta(outfit, perfil, reglas.paleta, reglas.color),
        formalidad=c_formalidad(outfit),
        textura=c_textura(outfit, reglas.texturas),
        mood=costo_mood(outfit, mood, rango_evento or RANGO_COMPLETO, reglas.mood),
    )
