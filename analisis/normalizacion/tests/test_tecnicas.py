"""Las tecnicas con imagenes sinteticas de luz conocida."""

import numpy as np
import pytest

from normalizacion.tecnicas import (
    NEUTRA,
    angulo,
    corregir,
    estimar_ref,
    estimar_t0,
    estimar_t1,
    estimar_t2,
)

from app.extraccion.color import lineal_a_srgb, srgb_a_lineal

LUZ_CALIDA = np.array([1.0, 0.8, 0.55])  # como una bombilla amarilla


def bajo_luz(reflectancia, luz, forma=(40, 40)) -> np.ndarray:
    """Una imagen sRGB uniforme: la reflectancia (RGB lineal) iluminada por `luz`."""
    lineal = np.broadcast_to(np.asarray(reflectancia) * luz, (*forma, 3))
    return np.round(lineal_a_srgb(lineal)).astype(np.uint8)


def test_t0_no_cambia_nada():
    rgb = bajo_luz([0.3, 0.2, 0.1], LUZ_CALIDA)
    np.testing.assert_allclose(corregir(rgb, estimar_t0()), rgb, atol=1e-6)


def test_un_blanco_bajo_luz_calida_estima_esa_luz_y_queda_neutro():
    blanco = bajo_luz([0.6, 0.6, 0.6], LUZ_CALIDA)
    mascara = np.ones(blanco.shape[:2], bool)

    luz = estimar_t1(blanco, mascara)
    assert angulo(luz, LUZ_CALIDA) < 1.0

    corregido = srgb_a_lineal(corregir(blanco, luz))
    r, g, b = corregido[0, 0]
    assert abs(r - g) < 0.01 and abs(g - b) < 0.01


def test_t1_sin_ojo_visible_no_estima():
    rgb = bajo_luz([0.6, 0.6, 0.6], LUZ_CALIDA)
    assert estimar_t1(rgb, None) is None
    assert estimar_t1(rgb, np.zeros(rgb.shape[:2], bool)) is None


def test_t1_ignora_sombras_y_reflejos_del_ojo():
    ojo = bajo_luz([0.6, 0.6, 0.6], LUZ_CALIDA)
    ojo[:4] = 20  # sombra del parpado
    ojo[-2:] = 255  # reflejo saturado
    luz = estimar_t1(ojo, np.ones(ojo.shape[:2], bool))
    assert angulo(luz, LUZ_CALIDA) < 1.5


def test_t2_toma_el_color_de_los_brillos():
    piel_lineal = np.array([0.35, 0.18, 0.10])
    rgb = bajo_luz(piel_lineal, LUZ_CALIDA * 0.6)
    # Unos pocos brillos especulares: casi solo la luz, sin saturar.
    rgb[:2, :10] = np.round(lineal_a_srgb(LUZ_CALIDA * 0.95)).astype(np.uint8)
    piel = np.ones(rgb.shape[:2], bool)
    luz = estimar_t2(rgb, piel, np.zeros_like(piel), fraccion=0.01)
    assert angulo(luz, LUZ_CALIDA) < 3.0
    # Sin brillos, T2 confunde la piel con la luz: es su limite conocido.
    sin_brillos = bajo_luz(piel_lineal, LUZ_CALIDA * 0.6)
    assert angulo(estimar_t2(sin_brillos, piel, np.zeros_like(piel)), LUZ_CALIDA) > 10


def test_ref_sin_tarjeta_no_estima():
    assert estimar_ref(None) is None
    assert angulo(estimar_ref(np.array([0.2, 0.2, 0.2])), NEUTRA) == pytest.approx(0, abs=1e-6)


def test_angulo():
    assert angulo([1, 0, 0], [0, 1, 0]) == pytest.approx(90)
    assert angulo([1, 1, 1], [2, 2, 2]) == pytest.approx(0, abs=1e-6)
