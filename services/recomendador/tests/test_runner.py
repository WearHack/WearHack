"""El log estructurado de cada corrida de job (#50)."""

import logging

import pytest

from app.jobs import _runner
from app.jobs._runner import ResultadoJob, ejecutar


@pytest.fixture(autouse=True)
def sin_configurar_logs(monkeypatch):
    # configurar_logs limpia los manejadores de la raiz, y con ellos el de caplog.
    monkeypatch.setattr(_runner, "configurar_logs", lambda *_: None)


def corrida(caplog) -> logging.LogRecord:
    registros = [r for r in caplog.records if hasattr(r, "usuarios_afectados")]
    assert len(registros) == 1
    return registros[0]


def test_una_corrida_deja_job_umbral_usuarios_y_timestamp(caplog):
    caplog.set_level(logging.INFO)

    codigo = ejecutar("prueba", lambda: ResultadoJob(umbral_alcanzado=True, usuarios_afectados=3))

    assert codigo == 0
    registro = corrida(caplog)
    assert registro.job == "prueba"
    assert registro.estado == "termina"
    assert registro.umbral_alcanzado is True
    assert registro.usuarios_afectados == 3
    assert registro.timestamp.endswith("Z")


def test_un_job_sin_resultado_deja_la_corrida_igual(caplog):
    caplog.set_level(logging.INFO)

    assert ejecutar("prueba", lambda: None) == 0

    registro = corrida(caplog)
    assert registro.umbral_alcanzado is None
    assert registro.usuarios_afectados is None


def test_un_job_que_falla_sale_con_1_y_deja_la_corrida(caplog):
    caplog.set_level(logging.INFO)

    def falla():
        raise RuntimeError("roto")

    assert ejecutar("prueba", falla) == 1
    assert corrida(caplog).estado == "fallo"
