"""Ningun error devuelve ni registra datos de la peticion (#51).

Se usa un base64 falso: ninguna prueba lleva imagenes reales.
"""

import logging

from fastapi import FastAPI
from fastapi.testclient import TestClient
from pydantic import BaseModel

from app.errores import registrar_manejadores
from app.main import app as app_real

IMAGEN_FALSA = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="


class Cuerpo(BaseModel):
    imagen: bytes
    edad: int


def app_de_prueba() -> FastAPI:
    app = FastAPI()
    registrar_manejadores(app)

    @app.post("/eco")
    async def eco(cuerpo: Cuerpo) -> dict:
        return {}

    @app.post("/roto")
    async def roto(cuerpo: Cuerpo) -> dict:
        raise ValueError(f"no se pudo leer {cuerpo.imagen!r}")

    return app


def todo_lo_registrado(caplog) -> str:
    return "\n".join(f"{r.getMessage()} {r.__dict__}" for r in caplog.records)


def test_un_422_no_devuelve_el_input(caplog):
    caplog.set_level(logging.INFO)
    cliente = TestClient(app_de_prueba())

    respuesta = cliente.post("/eco", json={"imagen": IMAGEN_FALSA, "edad": "no es numero"})

    assert respuesta.status_code == 422
    assert IMAGEN_FALSA not in respuesta.text
    assert "no es numero" not in respuesta.text
    assert respuesta.json()["detail"][0]["loc"] == ["body", "edad"]
    assert IMAGEN_FALSA not in todo_lo_registrado(caplog)


def test_un_500_no_devuelve_ni_registra_el_mensaje_de_la_excepcion(caplog):
    caplog.set_level(logging.INFO)
    cliente = TestClient(app_de_prueba(), raise_server_exceptions=False)

    respuesta = cliente.post("/roto", json={"imagen": IMAGEN_FALSA, "edad": 30})

    assert respuesta.status_code == 500
    assert respuesta.json() == {"detail": "Error interno"}
    registrado = todo_lo_registrado(caplog)
    assert "ValueError" in registrado
    assert IMAGEN_FALSA not in registrado
    assert "no se pudo leer" not in registrado


def test_el_servicio_real_tiene_los_manejadores():
    assert set(app_real.exception_handlers) >= {Exception}
    cliente = TestClient(app_real)

    respuesta = cliente.post(
        "/v1/colorimetria/analizar", content=IMAGEN_FALSA, headers={"content-type": "text/plain"}
    )

    assert respuesta.status_code == 422
    assert IMAGEN_FALSA not in respuesta.text
