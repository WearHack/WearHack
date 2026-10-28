"""Versiones de centroides en Mongo y su recarga en el servicio."""

import pytest

from app.centroides import CentroidesVigentes, RepositorioCentroides
from app.jobs.publicar_centroides import argumentos, ejecutar
from tests import falsos


@pytest.fixture
def coleccion():
    return falsos.ColeccionFalsa()


@pytest.fixture
def repositorio(coleccion):
    return RepositorioCentroides(coleccion)


def test_publicar_no_activa_y_activar_si(repositorio):
    repositorio.publicar(falsos.artefacto("v1"))
    assert repositorio.version_vigente() is None

    repositorio.activar("v1")
    assert repositorio.version_vigente() == "v1"


def test_una_version_publicada_no_se_reescribe(repositorio):
    repositorio.publicar(falsos.artefacto("v1"))
    with pytest.raises(ValueError, match="ya existe"):
        repositorio.publicar(falsos.artefacto("v1"))


def test_no_se_activa_lo_que_no_esta_publicado(repositorio):
    with pytest.raises(ValueError, match="no esta publicada"):
        repositorio.activar("v9")


def test_revertir_deja_una_sola_vigente(repositorio, coleccion):
    for v in ("v1", "v2"):
        repositorio.publicar(falsos.artefacto(v))
    repositorio.activar("v2")
    repositorio.activar("v1")

    assert [d["_id"] for d in coleccion.documentos.values() if d["vigente"]] == ["v1"]


def test_un_artefacto_invalido_no_se_publica(repositorio, coleccion):
    with pytest.raises(ValueError):
        repositorio.publicar({"version": "rota"})
    assert not coleccion.documentos


class Reloj:
    def __init__(self) -> None:
        self.ahora = 0.0

    def __call__(self) -> float:
        return self.ahora


def test_recarga_solo_cuando_toca_y_cuando_cambia(repositorio):
    reloj = Reloj()
    vigentes = CentroidesVigentes(repositorio, intervalo=60, reloj=reloj)
    assert vigentes.actual() is None

    repositorio.publicar(falsos.artefacto("v1"))
    repositorio.activar("v1")
    assert vigentes.actual() is None  # aun no toca mirar
    reloj.ahora = 60
    assert vigentes.actual().version == "v1"

    repositorio.publicar(falsos.artefacto("v2"))
    repositorio.activar("v2")
    reloj.ahora = 119
    assert vigentes.actual().version == "v1"
    reloj.ahora = 120
    assert vigentes.actual().version == "v2"


def test_si_mongo_falla_sigue_con_lo_que_tenia(repositorio, coleccion):
    repositorio.publicar(falsos.artefacto("v1"))
    repositorio.activar("v1")
    reloj = Reloj()
    vigentes = CentroidesVigentes(repositorio, intervalo=1, reloj=reloj)
    assert vigentes.actual().version == "v1"

    coleccion.falla = True
    reloj.ahora = 5
    assert vigentes.actual().version == "v1"


def test_una_version_vigente_rota_no_reemplaza_a_la_buena(repositorio, coleccion):
    repositorio.publicar(falsos.artefacto("v1"))
    repositorio.activar("v1")
    reloj = Reloj()
    vigentes = CentroidesVigentes(repositorio, intervalo=1, reloj=reloj)
    assert vigentes.actual().version == "v1"

    # Alguien la escribio a mano en Mongo, sin pasar por publicar.
    coleccion.insert_one({"_id": "v2", "artefacto": '{"version": "v2"}', "vigente": False})
    repositorio.activar("v2")
    reloj.ahora = 5
    assert vigentes.actual().version == "v1"


def test_el_comando_publica_y_activa(tmp_path, repositorio):
    import json

    ruta = tmp_path / "centroides.json"
    ruta.write_text(json.dumps(falsos.artefacto("v1")), encoding="utf-8")

    ejecutar(argumentos(["publicar", str(ruta), "--activar"]), repositorio)
    assert repositorio.version_vigente() == "v1"

    ejecutar(argumentos(["listar"]), repositorio)


def test_el_comando_rechaza_ordenes_desconocidas():
    with pytest.raises(SystemExit):
        argumentos(["borrar", "v1"])
