"""Medir y validar la tarjeta con fotos sinteticas."""

import numpy as np
import pytest

from normalizacion.tarjeta import cargar_cajas, guardar_cajas, medir, validar
from normalizacion.tecnicas import angulo

from app.extraccion.color import lineal_a_srgb

LUZ = np.array([1.0, 0.85, 0.65])
CAJAS = {"blanco": (10, 10, 50, 50), "gris": (60, 10, 100, 50), "negro": (110, 10, 150, 50)}


def foto(blanco=(0.85, 0.85, 0.85), gris=(0.18, 0.18, 0.18), negro=(0.03, 0.03, 0.03)):
    """Tres parches bajo `LUZ` sobre un fondo medio."""
    lineal = np.full((60, 160, 3), 0.1)
    for (x0, y0, x1, y1), refl in zip(CAJAS.values(), (blanco, gris, negro), strict=True):
        lineal[y0:y1, x0:x1] = np.asarray(refl) * LUZ
    return np.round(lineal_a_srgb(lineal)).astype(np.uint8)


def parches(imagen, cajas=CAJAS):
    return {n: medir(imagen, c) for n, c in cajas.items()}


def test_una_tarjeta_neutra_sirve_y_el_gris_ve_la_luz():
    p = parches(foto())
    resultado = validar(p)
    assert resultado.sirve, resultado.problemas
    assert resultado.angulo_blanco_gris < 1
    assert angulo(p["gris"].lineal, LUZ) < 1


def test_un_gris_con_tinte_no_sirve():
    resultado = validar(parches(foto(gris=(0.20, 0.17, 0.15))))
    assert not resultado.sirve
    assert "luces distintas" in " ".join(resultado.problemas)


def test_un_blanco_saturado_no_sirve():
    resultado = validar(parches(foto(blanco=(1.2, 1.2, 1.2))))
    assert not resultado.sirve
    assert "saturado" in " ".join(resultado.problemas)


def test_un_brillo_sobre_el_gris_no_sirve():
    imagen = foto()
    imagen[25:35, 70:90] = 235
    assert not validar(parches(imagen)).sirve


def test_la_caja_se_puede_marcar_en_cualquier_sentido():
    imagen = foto()
    al_reves = {n: (x1, y1, x0, y0) for n, (x0, y0, x1, y1) in CAJAS.items()}
    np.testing.assert_allclose(parches(imagen, al_reves)["gris"].lineal, parches(imagen)["gris"].lineal)


def test_una_caja_vacia_falla():
    with pytest.raises(ValueError):
        medir(foto(), (5, 5, 5, 5))


def test_las_cajas_se_guardan_y_se_leen(tmp_path):
    ruta = tmp_path / "boveda" / "tarjetas.json"
    guardar_cajas(ruta, {"P1_VEN_D1_R1_G": CAJAS})
    assert cargar_cajas(ruta) == {"P1_VEN_D1_R1_G": CAJAS}
    assert cargar_cajas(tmp_path / "no-existe.json") == {}
