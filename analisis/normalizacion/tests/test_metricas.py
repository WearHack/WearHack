"""ΔE00 contra los datos de prueba publicados, y el resto de piezas numericas."""

import math

import numpy as np
import pytest

from normalizacion.metricas import calidad, delta_e_00, ita, spearman

# Sharma, Wu y Dalal (2005), tabla 1: pares 1, 7, 17, 25 y 34.
PARES_SHARMA = [
    ((50.0, 2.6772, -79.7751), (50.0, 0.0, -82.7485), 2.0425),
    ((50.0, 0.0, 0.0), (50.0, -1.0, 2.0), 2.3669),
    ((50.0, 2.5, 0.0), (73.0, 25.0, -18.0), 27.1492),
    ((60.2574, -34.0099, 36.2677), (60.4626, -34.1751, 39.4387), 1.2644),
    ((2.0776, 0.0795, -1.1350), (0.9033, -0.0636, -0.5514), 0.9082),
]


@pytest.mark.parametrize(("lab1", "lab2", "esperado"), PARES_SHARMA)
def test_delta_e_00_coincide_con_la_referencia(lab1, lab2, esperado):
    assert float(delta_e_00(lab1, lab2)) == pytest.approx(esperado, abs=1e-4)
    # Es simetrica.
    assert float(delta_e_00(lab2, lab1)) == pytest.approx(esperado, abs=1e-4)


def test_delta_e_00_vectorizada():
    a = np.array([p[0] for p in PARES_SHARMA])
    b = np.array([p[1] for p in PARES_SHARMA])
    np.testing.assert_allclose(delta_e_00(a, b), [p[2] for p in PARES_SHARMA], atol=1e-4)


def test_spearman():
    assert spearman([1, 2, 3, 4], [10, 20, 30, 40]) == pytest.approx(1)
    assert spearman([1, 2, 3, 4], [9, 7, 5, 1]) == pytest.approx(-1)
    assert spearman([1, 2, 2, 3], [1, 2, 2, 3]) == pytest.approx(1)  # empates
    assert math.isnan(spearman([1, 2], [1, 2]))
    assert math.isnan(spearman([1, 1, 1], [1, 2, 3]))


def test_ita_baja_con_la_piel_mas_oscura():
    assert ita(70, 15) > ita(50, 20) > ita(35, 18)


def test_calidad_con_las_definiciones_del_cliente():
    rgb = np.full((10, 10, 3), 128, np.uint8)
    rgb[0, :5] = (255, 10, 10)  # 5 % con un canal saturado
    rgb[1, :2] = 0  # 2 % negro
    c = calidad(rgb)
    assert c["quemados_pct"] == pytest.approx(5)
    assert c["negros_pct"] == pytest.approx(2)
    assert calidad(np.full((10, 10, 3), 90, np.uint8))["nitidez"] == 0
    assert c["nitidez"] > 0
