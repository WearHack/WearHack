"""Piezas de la calibracion que no necesitan imagenes ni modelos."""

import json

import numpy as np
import pytest

from calibracion import configuracion
from calibracion.calibrar import PLIEGUES, Validacion, banda_ita, combinar, pliegues, seleccion_voraz
from calibracion.dataset import hash_del_manifiesto


def test_la_configuracion_dentro_de_un_repositorio_se_rechaza(tmp_path):
    (tmp_path / ".git").mkdir()
    ruta = tmp_path / "entrenamiento.json"
    ruta.write_text(json.dumps(dict.fromkeys(configuracion.CLAVES, str(tmp_path))))
    with pytest.raises(configuracion.ErrorDeConfiguracion, match="repositorio"):
        configuracion.cargar(ruta)


def test_los_datos_dentro_de_un_repositorio_se_rechazan(tmp_path):
    repo = tmp_path / "repo"
    (repo / ".git").mkdir(parents=True)
    fuera = tmp_path / "fuera"
    fuera.mkdir()
    ruta = fuera / "entrenamiento.json"
    ruta.write_text(
        json.dumps({"deep_armocromia": str(repo), "modelos_mediapipe": str(fuera), "salida": str(fuera)})
    )
    with pytest.raises(configuracion.ErrorDeConfiguracion, match="deep_armocromia"):
        configuracion.cargar(ruta)


def test_pliegues_estratificados():
    y = np.array(["A"] * 50 + ["B"] * 25)
    asignacion = pliegues(y, np.random.default_rng(42))
    for k in range(PLIEGUES):
        assert (y[asignacion == k] == "A").sum() == 10
        assert (y[asignacion == k] == "B").sum() == 5


def test_la_busqueda_voraz_encuentra_la_variable_que_separa(monkeypatch):
    rng = np.random.default_rng(0)
    n = 200
    y = np.array(["CALIDO", "FRIO"] * (n // 2))
    x = rng.normal(size=(n, 3))
    x[:, 1] += np.where(y == "CALIDO", 3, -3)
    monkeypatch.setattr("calibracion.calibrar.NOMBRES", ["ruido_1", "senal", "ruido_2"])
    elegidas, historial = seleccion_voraz(Validacion(x, pliegues(y, rng)), y)
    assert elegidas[0] == 1
    assert historial[0] > 0.95


def test_combinar_capas_en_estacion():
    estaciones = combinar(np.array(["CALIDO", "FRIO", None]), np.array(["ALTO", "BAJO", "ALTO"]))
    assert list(estaciones) == ["OTONO", "VERANO", None]


def test_bandas_ita():
    assert banda_ita(60) == "muy_clara"
    assert banda_ita(30) == "intermedia"
    assert banda_ita(-40) == "oscura"
    assert banda_ita(float("nan")) == "sin_piel"


def test_el_hash_del_manifiesto_no_depende_del_orden():
    filas = [("b.png", "2"), ("a.png", "1")]
    assert hash_del_manifiesto(filas) == hash_del_manifiesto(list(reversed(filas)))
