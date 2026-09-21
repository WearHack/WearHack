"""Comprueba lo unico que este esqueleto promete."""

from fastapi.testclient import TestClient

from app.main import app

cliente = TestClient(app)


def test_el_health_responde():
    respuesta = cliente.get("/health")

    assert respuesta.status_code == 200
    cuerpo = respuesta.json()
    assert cuerpo["servicio"] == "colorimetria"
    assert cuerpo["estado"] == "UP"


def test_el_analisis_declara_que_no_esta_implementado():
    """Un stub que inventara una temporada invitaria a montar el cliente
    encima de datos falsos."""
    respuesta = cliente.post(
        "/api/v1/colorimetria/analisis",
        json={"usuario_id": "u-1", "recorte_facial_clave": "rostros/u-1/recorte.jpg"},
    )

    assert respuesta.status_code == 501
