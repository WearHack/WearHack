"""Endpoint de colorimetria: `POST /v1/colorimetria/analizar` (respuestas G.39).

Lo llama el Core, nunca el telefono directamente. El cuerpo es el PNG del
recorte facial, crudo: el telefono detecta el rostro, lo recorta y solo sube
eso (ADR 0016). La foto completa nunca llega aqui, y el recorte no se guarda.

- `200`: la estacion y los colores medidos, con la forma que valida el Core
  (`ResultadoColorimetria`). Lo que el Core aun no lee va en campos extra.
- `413`: el recorte pasa del tope.
- `422`: el recorte no sirve (no es PNG, no hay rostro, no hay piel). El usuario
  puede repetir la foto.
- `503`: falta algo del servicio (no hay centroides vigentes, los modelos no son
  los de la calibracion). Reintentable.
"""

import logging

from fastapi import APIRouter, HTTPException, Request, status
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel, Field

from app.analisis import RecorteInvalido, ServicioColorimetria, ServicioNoDisponible
from app.config import ajustes

log = logging.getLogger(__name__)

router = APIRouter(prefix="/v1/colorimetria", tags=["colorimetria"])


class Lab(BaseModel):
    l: float  # noqa: E741 - es el nombre del canal, y el Core lo espera asi
    a: float
    b: float


class Probabilidades(BaseModel):
    estaciones: dict[str, float]
    subtono: dict[str, float]
    contraste: dict[str, float]


class ResultadoColorimetria(BaseModel):
    temporada: str = Field(description="PRIMAVERA, VERANO, OTONO o INVIERNO")
    confianza: float = Field(ge=0, le=1, description="Probabilidad de la temporada elegida")
    ejes: list[str] = Field(
        description="Variables que de verdad se usaron. Si falta el cabello, faltan las suyas: "
        "la recalibracion solo mueve lo medido (B.12)"
    )
    piel: Lab
    cabello: Lab | None = Field(description="Sin cabello visible no se mide ni se imputa")
    iris: Lab | None
    segunda_opcion: str
    probabilidades: Probabilidades
    version_centroides: str
    experimental: str | None = Field(
        description="Aviso del artefacto, por ejemplo que solo vale para el MVP academico"
    )


@router.post(
    "/analizar",
    response_model=ResultadoColorimetria,
    responses={413: {}, 422: {}, 503: {}},
    openapi_extra={
        "requestBody": {
            "required": True,
            "content": {"image/png": {"schema": {"type": "string", "format": "binary"}}},
        }
    },
)
async def analizar(request: Request) -> ResultadoColorimetria:
    """Clasifica la estacion de color a partir del recorte facial en PNG."""
    config = ajustes()
    if request.headers.get("content-type", "").split(";")[0].strip() != "image/png":
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "El cuerpo debe ser image/png")
    declarado = request.headers.get("content-length")
    if declarado and declarado.isdigit() and int(declarado) > config.max_recorte_bytes:
        raise HTTPException(
            status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, "El recorte es demasiado grande"
        )

    datos = bytearray()
    async for bloque in request.stream():
        datos += bloque
        if len(datos) > config.max_recorte_bytes:
            raise HTTPException(
                status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, "El recorte es demasiado grande"
            )

    servicio: ServicioColorimetria = request.app.state.colorimetria
    try:
        # MediaPipe es CPU y bloquea: fuera del bucle de eventos.
        resultado = await run_in_threadpool(servicio.analizar_png, bytes(datos))
    except RecorteInvalido as e:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, str(e)) from e
    except ServicioNoDisponible as e:
        log.error("Colorimetria no disponible: %s", e)
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, str(e)) from e
    return ResultadoColorimetria(**resultado)
