"""Respuestas de error sin datos de la peticion (#51; politica de datos seccion 10).

Por defecto FastAPI devuelve en un 422 el `input` que no valido, y ese input
puede ser una imagen en base64 o datos de un usuario. Y un error no controlado
deja en el log un traceback cuyo mensaje puede llevar lo mismo. Aqui:

- 422: solo donde fallo (`loc`), que fallo (`msg`) y el tipo. Sin `input` ni `ctx`.
- 500: un mensaje generico. En el log, el tipo de excepcion y donde fallo,
  pero no su mensaje.

Copia literal en colorimetria y recomendador: si cambias uno, cambia el otro.
"""

import logging
import traceback

from fastapi import FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

log = logging.getLogger(__name__)


def errores_sin_datos(errores) -> list[dict]:
    return [
        {"loc": list(e.get("loc", ())), "msg": e.get("msg", ""), "type": e.get("type", "")}
        for e in errores
    ]


async def validacion_invalida(request: Request, exc: RequestValidationError) -> JSONResponse:
    detalle = errores_sin_datos(exc.errors())
    log.warning(
        "Peticion invalida en %s %s",
        request.method,
        request.url.path,
        extra={"campos": [".".join(str(p) for p in e["loc"]) for e in detalle]},
    )
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, content={"detail": detalle}
    )


def traza(exc: Exception) -> list[str]:
    """Donde fallo (archivo, linea, funcion), sin el mensaje ni el codigo fuente."""
    return [f"{f.filename}:{f.lineno} en {f.name}" for f in traceback.extract_tb(exc.__traceback__)]


async def error_no_controlado(request: Request, exc: Exception) -> JSONResponse:
    log.error(
        "Error no controlado en %s %s: %s",
        request.method,
        request.url.path,
        type(exc).__name__,
        extra={"traza": traza(exc)},
    )
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={"detail": "Error interno"},
    )


def registrar_manejadores(app: FastAPI) -> None:
    app.add_exception_handler(RequestValidationError, validacion_invalida)
    app.add_exception_handler(Exception, error_no_controlado)
