"""Modelos del motor y sus enums.

Los valores salen de los enums del esquema de Mongo (`infra/datos/`): si uno
cambia alli, cambia aqui. Solo estan los campos que el motor usa hoy; cada
regla nueva anade los suyos.
"""

from dataclasses import dataclass
from enum import IntEnum, StrEnum

from app.motor.color import ColorLCh


class Slot(StrEnum):
    TORSO_SUPERIOR = "TORSO_SUPERIOR"
    TORSO_INFERIOR = "TORSO_INFERIOR"
    CUERPO_COMPLETO = "CUERPO_COMPLETO"
    CALZADO = "CALZADO"
    EXTERIOR = "EXTERIOR"
    ACCESORIO_CUELLO = "ACCESORIO_CUELLO"
    ACCESORIO_RELOJ = "ACCESORIO_RELOJ"
    ACCESORIO_CINTURA = "ACCESORIO_CINTURA"
    ACCESORIO_CABEZA = "ACCESORIO_CABEZA"
    ACCESORIO_BOLSO = "ACCESORIO_BOLSO"
    ACCESORIO_OJOS = "ACCESORIO_OJOS"
    ACCESORIO_JOYERIA = "ACCESORIO_JOYERIA"


class Patron(StrEnum):
    LISO = "LISO"
    RAYAS = "RAYAS"
    CUADROS = "CUADROS"
    PUNTOS = "PUNTOS"
    FLORAL = "FLORAL"
    ANIMAL = "ANIMAL"
    GEOMETRICO = "GEOMETRICO"
    OTRO_ESTAMPADO = "OTRO_ESTAMPADO"


class Textura(StrEnum):
    LISO_LIGERO = "LISO_LIGERO"
    DENIM = "DENIM"
    PUNTO = "PUNTO"
    PANO = "PANO"
    CUERO = "CUERO"
    SATIN = "SATIN"
    LINO = "LINO"
    DEPORTIVO = "DEPORTIVO"
    ACOLCHADO = "ACOLCHADO"
    OTRA = "OTRA"


class Clima(StrEnum):
    FRIO = "FRIO"
    TEMPLADO = "TEMPLADO"
    CALIDO = "CALIDO"


class Formalidad(IntEnum):
    """Niveles ordinales. En Mongo se guardan por nombre: `Formalidad[nombre]`."""

    DEPORTIVO = 0
    CASUAL = 1
    SMART_CASUAL = 2
    FORMAL = 3


RangoFormalidad = tuple[Formalidad, Formalidad]

# Los que forman el outfit. Accesorios y joyeria acompanan, pero no cuentan ni
# para la prenda puente ni para decidir si dos outfits son distintos.
SLOTS_PRINCIPALES = frozenset(
    {Slot.TORSO_SUPERIOR, Slot.TORSO_INFERIOR, Slot.CUERPO_COMPLETO, Slot.CALZADO, Slot.EXTERIOR}
)


@dataclass(frozen=True)
class Prenda:
    id: str
    slot: Slot
    patron: Patron = Patron.LISO
    textura: Textura | None = None
    # Rango (min, max); None en los accesorios neutros, que no cuentan.
    formalidad: RangoFormalidad | None = None
    color: ColorLCh | None = None
    clima_apto: frozenset[Clima] = frozenset(Clima)


Outfit = tuple[Prenda, ...]
