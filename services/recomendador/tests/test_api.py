"""El endpoint `POST /v1/recomendacion/generar`, con Mongo sustituido."""

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.pesos import RepositorioPesosMongo
from tests.test_pesos import SEMBRADO, ColeccionFalsa

RUTA = "/v1/recomendacion/generar"


def prenda(id_, slot, lab, **extra):
    return {
        "id": id_,
        "slot_outfit": slot,
        "lab": lab,
        "tipo": "CAMISETA",
        "textura": extra.pop("textura", "LISO_LIGERO"),
        "patron": extra.pop("patron", "LISO"),
        "formalidad": extra.pop("formalidad", {"min": "CASUAL", "max": "SMART_CASUAL"}),
        "clima_apto": extra.pop("clima_apto", ["TEMPLADO", "CALIDO"]),
        "version_esquema": 1,
        **extra,
    }


# Un closet pequeno que da para varios outfits distintos.
CLOSET = [
    prenda("camisa-azul", "TORSO_SUPERIOR", [45.0, 5.0, -35.0]),
    prenda("camiseta-blanca", "TORSO_SUPERIOR", [95.0, 0.0, 1.0]),
    prenda("camiseta-roja", "TORSO_SUPERIOR", [50.0, 55.0, 30.0]),
    prenda("jean", "TORSO_INFERIOR", [35.0, 2.0, -20.0], textura="DENIM"),
    prenda("pantalon-beige", "TORSO_INFERIOR", [75.0, 3.0, 15.0]),
    prenda("tenis-blancos", "CALZADO", [92.0, 0.0, 2.0], textura=None),
    prenda("botas-cafe", "CALZADO", [30.0, 10.0, 18.0], textura=None),
    prenda("reloj", "ACCESORIO_RELOJ", [20.0, 0.0, 0.0], textura=None, formalidad=None),
]


@pytest.fixture
def cliente():
    pesos = ColeccionFalsa(
        {"_id": "u-con-pesos", "color": 0.5, "paleta": 0.1, "formalidad": 0.3, "textura": 0.1}
    )
    app.state.pesos = RepositorioPesosMongo(ColeccionFalsa(SEMBRADO), pesos, intervalo=60)
    yield TestClient(app)
    del app.state.pesos


def pedir(cliente, **cambios):
    cuerpo = {
        "usuario_id": "u-1",
        "contexto": {"clima": "TEMPLADO", "mood": "RELAJADO"},
        "candidatos": CLOSET,
        **cambios,
    }
    return cliente.post(RUTA, json=cuerpo)


def test_genera_outfits_distintos_con_ids_del_closet(cliente):
    r = pedir(cliente)

    assert r.status_code == 200
    cuerpo = r.json()
    outfits = cuerpo["outfits"]
    assert 1 <= len(outfits) <= 3
    ids = {p["id"] for p in CLOSET}
    for o in outfits:
        assert set(o["prendas"]) <= ids
        assert set(o["componentes"]) == {"color", "paleta", "formalidad", "textura", "mood"}
    costos = [o["costo"] for o in outfits]
    assert costos == sorted(costos)
    assert cuerpo["origen_pesos"] == "iniciales"


def test_sin_perfil_la_paleta_no_cuenta(cliente):
    sin = pedir(cliente).json()
    con = pedir(
        cliente,
        perfil_color={
            "probabilidades": {"PRIMAVERA": 0.1, "VERANO": 0.6, "OTONO": 0.1, "INVIERNO": 0.2}
        },
    ).json()

    assert sin["pesos"]["paleta"] == 0
    assert con["pesos"]["paleta"] == 0.25


def test_usa_los_pesos_personales_si_los_hay(cliente):
    cuerpo = pedir(cliente, usuario_id="u-con-pesos").json()

    assert cuerpo["origen_pesos"] == "usuario"
    assert cuerpo["pesos"]["color"] == 0.5


def test_el_dress_code_filtra(cliente):
    """Nada del closet llega a FORMAL: no hay outfit, y no es un error."""
    r = pedir(
        cliente,
        contexto={"clima": "TEMPLADO", "formalidad_evento": {"min": "FORMAL", "max": "FORMAL"}},
    )

    assert r.status_code == 200
    assert r.json()["outfits"] == []


def test_un_closet_vacio_no_es_un_error(cliente):
    r = pedir(cliente, candidatos=[])
    assert r.status_code == 200
    assert r.json()["outfits"] == []


@pytest.mark.parametrize(
    "candidato",
    [
        prenda("x", "TORSO_SUPERIOR", [50.0, 0.0]),  # lab incompleto
        prenda("x", "PIERNA", [50.0, 0.0, 0.0]),  # slot que no existe
        prenda(
            "x", "TORSO_SUPERIOR", [50.0, 0.0, 0.0], formalidad={"min": "FORMAL", "max": "CASUAL"}
        ),
        prenda("x", "TORSO_SUPERIOR", [50.0, 0.0, 0.0], clima_apto=[]),
    ],
)
def test_un_candidato_invalido_es_422(cliente, candidato):
    assert pedir(cliente, candidatos=[candidato]).status_code == 422


def test_ids_repetidos_es_422(cliente):
    repetido = prenda("x", "TORSO_SUPERIOR", [50.0, 0.0, 0.0])
    assert pedir(cliente, candidatos=[repetido, repetido]).status_code == 422


def test_probabilidades_fuera_de_rango_es_422(cliente):
    r = pedir(cliente, perfil_color={"probabilidades": {"OTONO": 1.5}})
    assert r.status_code == 422


def test_la_ruta_del_stub_ya_no_existe(cliente):
    assert cliente.post("/api/v1/recomendador/outfits", json={}).status_code == 404
