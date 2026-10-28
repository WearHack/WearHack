"""El endpoint `POST /v1/colorimetria/analizar`, con el servicio sustituido."""

import pytest
from fastapi.testclient import TestClient

from app.analisis import RecorteInvalido, ServicioNoDisponible
from app.config import ajustes
from app.main import app
from tests import falsos

RUTA = "/v1/colorimetria/analizar"

RESULTADO = {
    "temporada": "OTONO",
    "confianza": 0.61,
    "ejes": ["piel_calidez", "contraste"],
    "piel": {"l": 66.1, "a": 12.0, "b": 20.5},
    "cabello": None,
    "iris": {"l": 30.0, "a": 8.0, "b": 15.0},
    "segunda_opcion": "PRIMAVERA",
    "probabilidades": {
        "estaciones": {"PRIMAVERA": 0.2, "VERANO": 0.1, "OTONO": 0.61, "INVIERNO": 0.09},
        "subtono": {"CALIDO": 0.81, "FRIO": 0.19},
        "contraste": {"ALTO": 0.7, "BAJO": 0.3},
    },
    "version_centroides": "prueba-v1",
    "experimental": "Solo pruebas",
}


class ServicioFalso:
    def __init__(self, respuesta=None, error=None) -> None:
        self.respuesta = respuesta
        self.error = error
        self.recibido = None

    def analizar_png(self, datos: bytes) -> dict:
        self.recibido = datos
        if self.error:
            raise self.error
        return self.respuesta


@pytest.fixture
def cliente():
    yield TestClient(app)
    if hasattr(app.state, "colorimetria"):
        del app.state.colorimetria


def enviar(cliente, servicio, cuerpo=b"png", tipo="image/png"):
    app.state.colorimetria = servicio
    return cliente.post(RUTA, content=cuerpo, headers={"content-type": tipo})


def test_devuelve_lo_que_lee_el_core(cliente):
    servicio = ServicioFalso(RESULTADO)
    r = enviar(cliente, servicio, falsos.png())

    assert r.status_code == 200
    cuerpo = r.json()
    # Los campos de ResultadoColorimetria del Core, con sus nombres exactos.
    for campo in ("temporada", "confianza", "ejes", "piel", "cabello", "iris"):
        assert campo in cuerpo
    assert cuerpo["piel"] == {"l": 66.1, "a": 12.0, "b": 20.5}
    assert cuerpo["cabello"] is None
    assert servicio.recibido == falsos.png()


def test_el_cuerpo_tiene_que_ser_png(cliente):
    r = enviar(cliente, ServicioFalso(RESULTADO), tipo="application/json")
    assert r.status_code == 422


def test_un_recorte_demasiado_grande_se_rechaza(cliente):
    cuerpo = b"x" * (ajustes().max_recorte_bytes + 1)
    r = enviar(cliente, ServicioFalso(RESULTADO), cuerpo)
    assert r.status_code == 413


def test_un_recorte_que_no_sirve_es_422(cliente):
    r = enviar(cliente, ServicioFalso(error=RecorteInvalido("No se detecto un rostro")))
    assert r.status_code == 422
    assert "rostro" in r.json()["detail"]


def test_sin_centroides_es_503(cliente):
    r = enviar(cliente, ServicioFalso(error=ServicioNoDisponible("No hay centroides")))
    assert r.status_code == 503


def test_la_ruta_del_stub_ya_no_existe(cliente):
    r = cliente.post("/api/v1/colorimetria/analisis", json={})
    assert r.status_code == 404
