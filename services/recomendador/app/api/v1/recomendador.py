"""Endpoint del recomendador. Stub.

El motor es combinatorio: genera candidatos cruzando las prendas del closet por
slot y los ordena con un vector de pesos por usuario. No hay modelo entrenado
ni lo va a haber por ahora, y es lo correcto: con decenas de prendas por
usuario, el espacio de combinaciones se recorre entero mas rapido de lo que
tardaria una inferencia.

De aqui salen tambien las prendas puente del catalogo de marcas aliadas, que
son las que monetizan el producto.
"""

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, Field

router = APIRouter(prefix="/api/v1/recomendador", tags=["recomendador"])


class PeticionOutfits(BaseModel):
    usuario_id: str = Field(description="Identificador del usuario")
    dias: int = Field(default=7, ge=1, le=14, description="Cuantos dias generar")


@router.post("/outfits", status_code=status.HTTP_501_NOT_IMPLEMENTED)
async def generar_outfits(peticion: PeticionOutfits) -> None:
    """Genera los outfits del periodo para un usuario.

    Devuelve 501 a proposito. Un stub que respondiera outfits inventados
    invitaria a montar el cliente encima de datos falsos, y el error saldria
    mucho mas tarde y mucho mas caro.
    """
    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="Sin implementar: pendiente el motor combinatorio.",
    )
