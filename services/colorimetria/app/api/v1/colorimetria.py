"""Endpoint de colorimetria. Stub.

El dispositivo recorta y normaliza el rostro y sube SOLO ese recorte al object
storage. Aqui llega la clave, nunca la foto completa.

La clasificacion sera nearest-centroid sobre el espacio Lab, no una CNN
profunda: el problema es de vecindad en un espacio de color pequeno y una red
profunda seria cara sin ser mas precisa.
"""

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, Field

router = APIRouter(prefix="/api/v1/colorimetria", tags=["colorimetria"])


class PeticionAnalisis(BaseModel):
    usuario_id: str = Field(description="Identificador del usuario")
    recorte_facial_clave: str = Field(
        description="Clave del recorte facial en el object storage. "
                    "Nunca la foto completa: esa no sale del dispositivo."
    )


@router.post("/analisis", status_code=status.HTTP_501_NOT_IMPLEMENTED)
async def analizar(peticion: PeticionAnalisis) -> None:
    """Clasifica la temporada de color del usuario.

    Devuelve 501 a proposito. Un stub que respondiera una temporada inventada
    invitaria a montar el cliente encima de datos falsos, y el error saldria
    mucho mas tarde y mucho mas caro.
    """
    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="Sin implementar: pendiente el clasificador nearest-centroid.",
    )
