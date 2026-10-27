"""Muestreo y variables con imagenes sinteticas. Ningun rostro en los tests."""

import math

import numpy as np
import pytest

from app.extraccion.color import srgb_a_hsv, srgb_a_lab
from app.extraccion.muestreo import Muestra, Variante, muestrear, pixeles_de_region
from app.extraccion.variables import calcular_variables


@pytest.mark.parametrize(
    ("rgb", "lab"),
    [
        ((255, 255, 255), (100.0, 0.0, 0.0)),
        ((0, 0, 0), (0.0, 0.0, 0.0)),
        ((255, 0, 0), (53.24, 80.09, 67.20)),
        ((0, 0, 255), (32.30, 79.19, -107.86)),
    ],
)
def test_srgb_a_lab_coincide_con_valores_de_referencia(rgb, lab):
    assert srgb_a_lab(np.array(rgb)) == pytest.approx(lab, abs=0.05)


def test_hsv_del_rojo_amarillo_y_gris():
    assert srgb_a_hsv(np.array([255, 0, 0])) == pytest.approx((0, 1, 1))
    assert srgb_a_hsv(np.array([255, 255, 0])) == pytest.approx((60, 1, 1))
    assert srgb_a_hsv(np.array([128, 128, 128]))[:2] == pytest.approx((0, 0))


def _region(colores: list[tuple[int, int, int]], repeticiones: list[int]):
    rgb = np.concatenate(
        [np.tile(np.array(c, np.uint8), (n, 1)) for c, n in zip(colores, repeticiones)]
    )[None, :, :]
    return pixeles_de_region(rgb, np.ones(rgb.shape[:2], bool))


def test_el_recorte_por_percentil_quita_brillos_y_sombras():
    # 80 % de piel, 10 % de brillo blanco y 10 % de sombra casi negra.
    lab, hsv = _region([(200, 150, 120), (255, 255, 255), (10, 5, 5)], [80, 10, 10])
    con_recorte = muestrear(lab, hsv, Variante("mediana", 15, 85), minimo_pixeles=1)
    piel = srgb_a_lab(np.array([200, 150, 120]))
    assert (con_recorte.L, con_recorte.a, con_recorte.b) == pytest.approx(tuple(piel))

    media = muestrear(lab, hsv, Variante("media"), minimo_pixeles=1)
    assert media.L != pytest.approx(piel[0], abs=1)


def test_region_por_debajo_del_minimo_no_da_muestra():
    lab, hsv = _region([(200, 150, 120)], [50])
    assert muestrear(lab, hsv, Variante("mediana", 10, 90), minimo_pixeles=100) is None
    assert muestrear(lab[:0], hsv[:0], Variante("mediana"), minimo_pixeles=1) is None


def _m(L, a, b, S=0.5, V=0.5):
    return Muestra(L=L, a=a, b=b, S=S, V=V, pixeles=100)


def test_variables_derivadas():
    v = calcular_variables(
        {"piel": _m(70, 12, 20), "cabello": _m(20, 3, 4), "ojos": _m(35, 2, 10)}
    )
    assert v["piel_calidez"] == pytest.approx(8)
    assert v["dL_piel_cabello"] == pytest.approx(50)
    assert v["contraste"] == pytest.approx(50)
    assert v["rango_L"] == pytest.approx(50)
    assert v["piel_b_L"] == pytest.approx(20 / 70)
    assert v["razon_croma_cabello_piel"] == pytest.approx(5 / math.hypot(12, 20))


def test_sin_cabello_el_contraste_cae_a_los_ojos_y_no_se_imputa():
    v = calcular_variables({"piel": _m(70, 12, 20), "cabello": None, "ojos": _m(35, 2, 10)})
    assert v["contraste"] == pytest.approx(35)
    assert math.isnan(v["cabello_L"])
    assert math.isnan(v["dL_piel_cabello"])


def test_sin_piel_no_hay_contraste():
    v = calcular_variables({"piel": None, "cabello": _m(20, 3, 4), "ojos": None})
    assert math.isnan(v["contraste"])
    assert math.isnan(v["rango_L"])
