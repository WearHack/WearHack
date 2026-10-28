"""El health, en sus dos rutas."""

from fastapi.testclient import TestClient

from app.main import app

cliente = TestClient(app)


def test_el_health_responde():
    respuesta = cliente.get("/health")

    assert respuesta.status_code == 200
    cuerpo = respuesta.json()
    assert cuerpo["servicio"] == "colorimetria"
    assert cuerpo["estado"] == "UP"


def test_el_health_tambien_responde_en_la_ruta_del_gateway():
    """Los seis servicios responden en /api/v1/<servicio>/health. Sin esto el
    gateway tendria que reescribir la ruta solo para los de Python."""
    respuesta = cliente.get("/api/v1/colorimetria/health")

    assert respuesta.status_code == 200
    assert respuesta.json()["servicio"] == "colorimetria"
