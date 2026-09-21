"""Health check del servicio.

Responde si el proceso esta en pie. No consulta dependencias todavia porque
todavia no hay ninguna; cuando las haya, readiness es el sitio donde mirarlas.
"""

from datetime import datetime, timezone

from fastapi import APIRouter
from pydantic import BaseModel

from app.config import ajustes

router = APIRouter(tags=["health"])


class Estado(BaseModel):
    servicio: str
    estado: str
    version: str
    momento: datetime


@router.get("/health", response_model=Estado)
async def health() -> Estado:
    config = ajustes()
    return Estado(
        servicio=config.servicio,
        estado="UP",
        version=config.version,
        momento=datetime.now(timezone.utc),
    )
