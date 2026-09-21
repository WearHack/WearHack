"""Comprueba lo unico que este esqueleto promete."""

from fastapi.testclient import TestClient

from app.main import app

cliente = TestClient(app)


def test_el_health_responde():
    respuesta = cliente.get("/health")

    assert respuesta.status_code == 200
    cuerpo = respuesta.json()
    assert cuerpo["servicio"] == "recomendador"
    assert cuerpo["estado"] == "UP"


def test_los_outfits_declaran_que_no_estan_implementados():
    """Un stub que inventara outfits invitaria a montar el cliente encima de
    datos falsos."""
    respuesta = cliente.post(
        "/api/v1/recomendador/outfits",
        json={"usuario_id": "u-1", "dias": 7},
    )

    assert respuesta.status_code == 501
