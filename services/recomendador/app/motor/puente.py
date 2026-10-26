"""Prenda puente: cuantos outfits buenos abre una prenda candidata.

Una candidata del catalogo de marcas aliadas se cruza con lo que el usuario ya
tiene en los slots principales. Una combinacion es **buena** si pasa los
filtros duros y su costo es menor o igual que la mediana de los outfits
actuales del usuario. Se recomienda si abre al menos `umbral` (5).

El costo de un outfit completo lo pone quien llama (`costo`): es el del motor,
y asi esta funcion se prueba sola. La misma funcion sirve para el lote nocturno
y para tiempo real.
"""

from collections.abc import Callable, Iterable, Iterator, Mapping, Sequence
from dataclasses import dataclass
from itertools import product
from math import inf
from statistics import mean, median

from app.motor.modelos import Clima, Outfit, Prenda, RangoFormalidad, Slot
from app.motor.reglas_duras import cumple_reglas_duras

# Los accesorios y la joyeria no cuentan para decidir si una prenda es puente.
SLOTS_PRINCIPALES = frozenset(
    {Slot.TORSO_SUPERIOR, Slot.TORSO_INFERIOR, Slot.CUERPO_COMPLETO, Slot.CALZADO, Slot.EXTERIOR}
)
UMBRAL_COMBINACIONES = 5

CostoOutfit = Callable[[Outfit], float]
CostoPaleta = Callable[[Prenda], float]
Eventos = Mapping[str, RangoFormalidad]


@dataclass(frozen=True)
class ReglasPuente:
    umbral: int = UMBRAL_COMBINACIONES


@dataclass(frozen=True)
class EvaluacionPuente:
    candidata: Prenda
    combinaciones_buenas: int
    eventos_nuevos: int
    costo_medio: float
    costo_paleta: float
    recomendada: bool


@dataclass(frozen=True)
class _Contexto:
    """Lo que depende del usuario y no de la candidata: se calcula una vez."""

    umbral_costo: float
    eventos_cubiertos: frozenset[str]


def generar_outfits(candidata: Prenda, closet: Iterable[Prenda]) -> Iterator[Outfit]:
    """Outfits que llevan la candidata y el resto sale del closet.

    Un outfit es un cuerpo completo, o torso superior mas inferior; con calzado
    y, opcionalmente, un exterior. Si la candidata es de otro tipo de slot
    (un accesorio), no genera nada.
    """
    if candidata.slot not in SLOTS_PRINCIPALES:
        return
    pool: dict[Slot, list[Prenda]] = {}
    for prenda in closet:
        if prenda.id != candidata.id and prenda.slot in SLOTS_PRINCIPALES:
            pool.setdefault(prenda.slot, []).append(prenda)
    pool[candidata.slot] = [candidata]

    cuerpos = [(v,) for v in pool.get(Slot.CUERPO_COMPLETO, [])]
    pares = list(product(pool.get(Slot.TORSO_SUPERIOR, []), pool.get(Slot.TORSO_INFERIOR, [])))
    exteriores = [None, *pool.get(Slot.EXTERIOR, [])]
    for base, calzado, exterior in product(
        [*cuerpos, *pares], pool.get(Slot.CALZADO, []), exteriores
    ):
        outfit = (*base, calzado, *((exterior,) if exterior else ()))
        if any(p.id == candidata.id for p in outfit):
            yield outfit


def pasa_dress_code(prenda: Prenda, rango_evento: RangoFormalidad) -> bool:
    """El rango de la prenda se cruza con el del evento; sin formalidad, siempre pasa."""
    if prenda.formalidad is None:
        return True
    minimo, maximo = prenda.formalidad
    return minimo <= rango_evento[1] and rango_evento[0] <= maximo


def eventos_habilitados(outfit: Outfit, eventos: Eventos) -> frozenset[str]:
    return frozenset(
        nombre
        for nombre, rango in eventos.items()
        if all(pasa_dress_code(p, rango) for p in outfit)
    )


def _contexto(
    outfits_actuales: Sequence[Outfit], costo: CostoOutfit, eventos: Eventos
) -> _Contexto:
    costos = [costo(o) for o in outfits_actuales]
    cubiertos = frozenset().union(*(eventos_habilitados(o, eventos) for o in outfits_actuales))
    # Sin outfits de referencia no hay mediana: todo outfit valido es bueno.
    return _Contexto(median(costos) if costos else inf, cubiertos)


def _evaluar(
    candidata: Prenda,
    closet: Sequence[Prenda],
    contexto: _Contexto,
    costo: CostoOutfit,
    eventos: Eventos,
    clima: Clima | None,
    costo_paleta: CostoPaleta | None,
    reglas: ReglasPuente,
) -> EvaluacionPuente:
    buenos: list[tuple[Outfit, float]] = []
    for outfit in generar_outfits(candidata, closet):
        if not cumple_reglas_duras(outfit, clima):
            continue
        c = costo(outfit)
        if c <= contexto.umbral_costo:
            buenos.append((outfit, c))

    habilitados = frozenset().union(*(eventos_habilitados(o, eventos) for o, _ in buenos))
    return EvaluacionPuente(
        candidata=candidata,
        combinaciones_buenas=len(buenos),
        eventos_nuevos=len(habilitados - contexto.eventos_cubiertos),
        costo_medio=mean(c for _, c in buenos) if buenos else inf,
        costo_paleta=costo_paleta(candidata) if costo_paleta else 0.0,
        recomendada=len(buenos) >= reglas.umbral,
    )


def evaluar_candidata(
    candidata: Prenda,
    closet: Sequence[Prenda],
    outfits_actuales: Sequence[Outfit],
    costo: CostoOutfit,
    eventos: Eventos,
    clima: Clima | None = None,
    costo_paleta: CostoPaleta | None = None,
    reglas: ReglasPuente = ReglasPuente(),
) -> EvaluacionPuente:
    contexto = _contexto(outfits_actuales, costo, eventos)
    return _evaluar(candidata, closet, contexto, costo, eventos, clima, costo_paleta, reglas)


def rankear_puentes(
    candidatas: Iterable[Prenda],
    closet: Sequence[Prenda],
    outfits_actuales: Sequence[Outfit],
    costo: CostoOutfit,
    eventos: Eventos,
    clima: Clima | None = None,
    costo_paleta: CostoPaleta | None = None,
    reglas: ReglasPuente = ReglasPuente(),
) -> list[EvaluacionPuente]:
    """Las candidatas que son puente, de mejor a peor.

    Orden: mas combinaciones buenas; y en empate, mas eventos nuevos, menor costo
    medio y menor C_paleta, en ese orden.
    """
    contexto = _contexto(outfits_actuales, costo, eventos)
    evaluaciones = (
        _evaluar(c, closet, contexto, costo, eventos, clima, costo_paleta, reglas)
        for c in candidatas
    )
    puentes = [e for e in evaluaciones if e.recomendada]
    return sorted(
        puentes,
        key=lambda e: (-e.combinaciones_buenas, -e.eventos_nuevos, e.costo_medio, e.costo_paleta),
    )
