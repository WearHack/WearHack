"""Motor combinatorio: de un closet y un contexto salen 3 outfits distintos.

1. Filtro de contexto: fuera lo que no sirve para el clima o el evento.
2. Desde unas 10 anclas distintas (torsos y cuerpos completos), se completa el
   outfit slot por slot escogiendo en cada paso la prenda de menor costo y
   respetando las reglas duras.
3. Se ordenan las candidatas por costo y se escogen la mejor y las siguientes
   que difieran de todas las ya escogidas en al menos 2 prendas principales.

Los pesos los pone un repositorio: los iniciales salen de `configuracion`
(documento `recomendacion`) y los personales de la coleccion del usuario.
"""

from collections.abc import Callable, Iterable, Mapping, Sequence
from dataclasses import dataclass, field, replace
from itertools import zip_longest
from typing import Protocol

from app.motor.costos import (
    PESOS_INICIALES,
    Componentes,
    PerfilColor,
    Pesos,
    ReglasCosto,
    componentes,
)
from app.motor.filtros import filtrar_por_contexto
from app.motor.modelos import (
    SLOTS_PRINCIPALES,
    Clima,
    Outfit,
    Prenda,
    RangoFormalidad,
    Slot,
)
from app.motor.mood import Mood
from app.motor.reglas_duras import cumple_reglas_duras, respeta_maximo_no_lisas

# Que slots se rellenan, y en que orden, segun el slot del ancla. El exterior va
# siempre al final: es opcional, y en el ultimo paso se comprueban todas las
# reglas duras, incluida la de capas en frio.
PLAN_POR_ANCLA: Mapping[Slot, tuple[Slot, ...]] = {
    Slot.TORSO_SUPERIOR: (Slot.TORSO_INFERIOR, Slot.CALZADO, Slot.EXTERIOR),
    Slot.TORSO_INFERIOR: (Slot.TORSO_SUPERIOR, Slot.CALZADO, Slot.EXTERIOR),
    Slot.CUERPO_COMPLETO: (Slot.CALZADO, Slot.EXTERIOR),
}
SLOTS_OPCIONALES = frozenset({Slot.EXTERIOR})


@dataclass(frozen=True)
class Contexto:
    clima: Clima | None = None
    rango_evento: RangoFormalidad | None = None
    mood: Mood | None = None
    perfil: PerfilColor | None = None


@dataclass(frozen=True)
class ReglasMotor:
    n_anclas: int = 10
    n_outfits: int = 3
    diferencia_minima: int = 2
    costo: ReglasCosto = ReglasCosto()


@dataclass(frozen=True)
class OutfitPuntuado:
    prendas: Outfit
    costo: float
    componentes: Componentes


class RepositorioPesos(Protocol):
    def pesos_iniciales(self) -> Pesos: ...

    def pesos_usuario(self, usuario_id: str) -> Pesos | None: ...


@dataclass
class RepositorioPesosEnMemoria:
    """Para pruebas y para arrancar sin Mongo."""

    iniciales: Pesos = PESOS_INICIALES
    personales: dict[str, Pesos] = field(default_factory=dict)

    def pesos_iniciales(self) -> Pesos:
        return self.iniciales

    def pesos_usuario(self, usuario_id: str) -> Pesos | None:
        return self.personales.get(usuario_id)


def pesos_para(usuario_id: str, repositorio: RepositorioPesos, perfil: PerfilColor | None) -> Pesos:
    """Los personales si los hay; si no, los iniciales. Sin perfil, w_paleta = 0."""
    pesos = repositorio.pesos_usuario(usuario_id) or repositorio.pesos_iniciales()
    return replace(pesos, paleta=0.0) if perfil is None else pesos


def puntuar(
    outfit: Outfit, contexto: Contexto, pesos: Pesos, reglas: ReglasMotor = ReglasMotor()
) -> OutfitPuntuado:
    partes = componentes(
        outfit, contexto.perfil, contexto.mood, contexto.rango_evento, reglas.costo
    )
    w_mood = reglas.costo.mood.w_mood if contexto.mood else 0.0
    return OutfitPuntuado(outfit, partes.total(pesos, w_mood), partes)


def funcion_costo(
    contexto: Contexto, pesos: Pesos, reglas: ReglasMotor = ReglasMotor()
) -> Callable[[Outfit], float]:
    """El costo de un outfit completo, listo para pasarselo a la prenda puente."""
    return lambda outfit: puntuar(outfit, contexto, pesos, reglas).costo


def elegir_anclas(prendas: Sequence[Prenda], n: int) -> list[Prenda]:
    """Hasta `n` anclas, alternando slots para no empezar siempre por lo mismo."""
    por_slot = [[p for p in prendas if p.slot == slot] for slot in PLAN_POR_ANCLA]
    intercaladas = (p for ronda in zip_longest(*por_slot) for p in ronda if p is not None)
    return [p for _, p in zip(range(n), intercaladas)]


def completar(
    ancla: Prenda,
    por_slot: Mapping[Slot, Sequence[Prenda]],
    costo: Callable[[Outfit], float],
    clima: Clima | None,
) -> Outfit | None:
    """Rellena el outfit slot por slot con la opcion de menor costo.

    None si algun slot obligatorio no tiene una prenda que respete las reglas.
    """
    plan = PLAN_POR_ANCLA[ancla.slot]
    outfit: Outfit = (ancla,)
    for paso, slot in enumerate(plan):
        opciones = [(*outfit, p) for p in por_slot.get(slot, ())]
        if slot in SLOTS_OPCIONALES:
            opciones.append(outfit)
        ultimo = paso == len(plan) - 1
        validas = [
            o
            for o in opciones
            if (cumple_reglas_duras(o, clima) if ultimo else respeta_maximo_no_lisas(o))
        ]
        if not validas:
            return None
        outfit = min(validas, key=costo)
    return outfit


def _diferencia(a: Outfit, b: Outfit) -> int:
    """En cuantas prendas principales difieren, mirando desde el mas grande."""
    ids_a = {p.id for p in a if p.slot in SLOTS_PRINCIPALES}
    ids_b = {p.id for p in b if p.slot in SLOTS_PRINCIPALES}
    return max(len(ids_a - ids_b), len(ids_b - ids_a))


def recomendar(
    closet: Iterable[Prenda],
    contexto: Contexto,
    pesos: Pesos,
    reglas: ReglasMotor = ReglasMotor(),
) -> list[OutfitPuntuado]:
    """Hasta `n_outfits` outfits, de menor a mayor costo, distintos entre si."""
    aptas = [
        p
        for p in filtrar_por_contexto(closet, contexto.clima, contexto.rango_evento)
        if p.slot in SLOTS_PRINCIPALES
    ]
    por_slot: dict[Slot, list[Prenda]] = {}
    for prenda in aptas:
        por_slot.setdefault(prenda.slot, []).append(prenda)

    costo = funcion_costo(contexto, pesos, reglas)
    candidatas: dict[frozenset[str], Outfit] = {}
    for ancla in elegir_anclas(aptas, reglas.n_anclas):
        outfit = completar(ancla, por_slot, costo, contexto.clima)
        if outfit is not None:
            candidatas.setdefault(frozenset(p.id for p in outfit), outfit)

    puntuadas = sorted(
        (puntuar(o, contexto, pesos, reglas) for o in candidatas.values()),
        key=lambda o: (o.costo, sorted(p.id for p in o.prendas)),
    )
    elegidas: list[OutfitPuntuado] = []
    for candidata in puntuadas:
        if all(
            _diferencia(candidata.prendas, e.prendas) >= reglas.diferencia_minima for e in elegidas
        ):
            elegidas.append(candidata)
        if len(elegidas) == reglas.n_outfits:
            break
    return elegidas


def recomendar_para_usuario(
    usuario_id: str,
    closet: Iterable[Prenda],
    contexto: Contexto,
    repositorio: RepositorioPesos,
    reglas: ReglasMotor = ReglasMotor(),
) -> list[OutfitPuntuado]:
    pesos = pesos_para(usuario_id, repositorio, contexto.perfil)
    return recomendar(closet, contexto, pesos, reglas)
