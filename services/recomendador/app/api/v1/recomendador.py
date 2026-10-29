"""Endpoint del recomendador: `POST /v1/recomendacion/generar` (respuestas G.39).

Lo llama el Core (modulo Outfits), nunca el telefono. El Core manda las prendas
candidatas en el propio request: este servicio no lee las colecciones del Core.
Tambien manda el contexto ya resuelto: el rango de formalidad del evento sale de
los dress codes del documento `outfits` de `configuracion`, que es del Core (G.41).

El motor es combinatorio: con decenas de prendas por usuario, el espacio de
combinaciones se recorre entero mas rapido de lo que tardaria una inferencia.

- `200`: hasta `n_outfits` outfits, de menor a mayor costo. Lista vacia si el
  closet no da para ninguno valido; que mensaje mostrar lo decide el Core.
- `422`: el DTO no valida.
"""

import math
from dataclasses import replace
from typing import Literal

from fastapi import APIRouter, Request
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel, Field, model_validator

from app.motor.color import ColorLCh
from app.motor.costos import Estacion, PerfilColor
from app.motor.modelos import Clima, Formalidad, Patron, Prenda, Slot, Textura
from app.motor.mood import Mood
from app.motor.motor import Contexto, recomendar
from app.pesos import RepositorioPesosMongo

router = APIRouter(prefix="/v1/recomendacion", tags=["recomendacion"])

# Un closet real son decenas de prendas. El tope acota el trabajo de una peticion.
MAX_CANDIDATOS = 1000

NivelFormalidad = Literal["DEPORTIVO", "CASUAL", "SMART_CASUAL", "FORMAL"]


class RangoFormalidad(BaseModel):
    min: NivelFormalidad
    max: NivelFormalidad

    @model_validator(mode="after")
    def _ordenado(self) -> "RangoFormalidad":
        if Formalidad[self.min] > Formalidad[self.max]:
            raise ValueError("formalidad.min no puede ser mayor que formalidad.max")
        return self

    def a_motor(self) -> tuple[Formalidad, Formalidad]:
        return Formalidad[self.min], Formalidad[self.max]


class Candidato(BaseModel):
    """Una prenda del closet, con los campos del esquema de `prendas` que usa el motor."""

    id: str = Field(min_length=1)
    slot_outfit: Slot
    lab: list[float] = Field(min_length=3, max_length=3, description="[L, a, b] en CIELAB D65")
    tipo: str | None = Field(default=None, description="Informativo: el motor no lo usa")
    textura: Textura | None = None
    patron: Patron = Patron.LISO
    formalidad: RangoFormalidad | None = Field(
        default=None, description="null en los accesorios neutros, que no cuentan"
    )
    clima_apto: list[Clima] = Field(min_length=1)
    version_esquema: int = Field(ge=1)

    def a_motor(self) -> Prenda:
        luz, a, b = self.lab
        color = ColorLCh(
            luz=luz, croma=math.hypot(a, b), matiz=math.degrees(math.atan2(b, a)) % 360
        )
        return Prenda(
            id=self.id,
            slot=self.slot_outfit,
            patron=self.patron,
            textura=self.textura,
            formalidad=self.formalidad.a_motor() if self.formalidad else None,
            color=color,
            clima_apto=frozenset(self.clima_apto),
        )


class ContextoPeticion(BaseModel):
    clima: Clima | None = None
    mood: Mood | None = None
    formalidad_evento: RangoFormalidad | None = Field(
        default=None, description="El dress code de la ocasion, ya resuelto por el Core"
    )
    ocasion: str | None = Field(default=None, description="Informativo")
    estacion: str | None = Field(
        default=None, description="Informativo: w_estacion esta apagado en Colombia"
    )


class PerfilColorPeticion(BaseModel):
    probabilidades: dict[Estacion, float] = Field(
        description="Probabilidad de cada estacion segun Colorimetria"
    )

    @model_validator(mode="after")
    def _probabilidades(self) -> "PerfilColorPeticion":
        if not self.probabilidades or any(not 0 <= p <= 1 for p in self.probabilidades.values()):
            raise ValueError("Las probabilidades van de 0 a 1")
        return self


class PeticionGenerar(BaseModel):
    usuario_id: str = Field(min_length=1, description="Dato de negocio: elige los pesos (G.39)")
    contexto: ContextoPeticion = ContextoPeticion()
    perfil_color: PerfilColorPeticion | None = Field(
        default=None, description="Sin perfil, la paleta no cuenta (w_paleta = 0)"
    )
    candidatos: list[Candidato] = Field(max_length=MAX_CANDIDATOS)

    @model_validator(mode="after")
    def _ids_unicos(self) -> "PeticionGenerar":
        ids = [c.id for c in self.candidatos]
        if len(ids) != len(set(ids)):
            raise ValueError("Hay candidatos con el mismo id")
        return self


class ComponentesRespuesta(BaseModel):
    color: float
    paleta: float
    formalidad: float
    textura: float
    mood: float


class OutfitRespuesta(BaseModel):
    prendas: list[str] = Field(description="Ids de los candidatos que forman el outfit")
    costo: float = Field(description="Menor es mejor")
    componentes: ComponentesRespuesta


class PesosRespuesta(BaseModel):
    color: float
    paleta: float
    formalidad: float
    textura: float


class RespuestaGenerar(BaseModel):
    outfits: list[OutfitRespuesta]
    pesos: PesosRespuesta = Field(description="Los que se usaron, ya con w_paleta = 0 sin perfil")
    origen_pesos: Literal["usuario", "iniciales"]


def generar(peticion: PeticionGenerar, repositorio: RepositorioPesosMongo) -> RespuestaGenerar:
    configuracion = repositorio.configuracion()
    perfil = PerfilColor(peticion.perfil_color.probabilidades) if peticion.perfil_color else None
    personales = repositorio.pesos_usuario(peticion.usuario_id)
    pesos = personales or configuracion.pesos_iniciales
    if perfil is None:
        pesos = replace(pesos, paleta=0.0)

    contexto = Contexto(
        clima=peticion.contexto.clima,
        rango_evento=(
            peticion.contexto.formalidad_evento.a_motor()
            if peticion.contexto.formalidad_evento
            else None
        ),
        mood=peticion.contexto.mood,
        perfil=perfil,
    )
    outfits = recomendar(
        [c.a_motor() for c in peticion.candidatos], contexto, pesos, configuracion.reglas
    )
    return RespuestaGenerar(
        outfits=[
            OutfitRespuesta(
                prendas=[p.id for p in o.prendas],
                costo=o.costo,
                componentes=ComponentesRespuesta(**vars(o.componentes)),
            )
            for o in outfits
        ],
        pesos=PesosRespuesta(**vars(pesos)),
        origen_pesos="usuario" if personales else "iniciales",
    )


@router.post("/generar", response_model=RespuestaGenerar)
async def generar_outfits(peticion: PeticionGenerar, request: Request) -> RespuestaGenerar:
    """Genera los outfits del dia a partir de las prendas candidatas del usuario."""
    repositorio: RepositorioPesosMongo = request.app.state.pesos
    # El motor es CPU y la lectura de pesos bloquea: fuera del bucle de eventos.
    return await run_in_threadpool(generar, peticion, repositorio)
