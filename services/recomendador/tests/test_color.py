import pytest

from app.motor.color import DENIM, ColorLCh, ReglasColor, costo_color, delta_matiz


def vivo(h: float) -> ColorLCh:
    return ColorLCh(luz=60, croma=50, matiz=h)


@pytest.mark.parametrize(
    ("h1", "h2", "esperado"),
    [(10, 350, 20), (0, 180, 180), (90, 90, 0), (350, 10, 20)],
)
def test_delta_matiz_toma_el_lado_corto(h1, h2, esperado):
    assert delta_matiz(h1, h2) == esperado


@pytest.mark.parametrize("delta", [0, 15, 30, 105, 120, 135, 160, 180])
def test_dentro_de_banda_cuesta_cero(delta):
    assert costo_color(vivo(0), vivo(delta)) == 0.0


def test_fuera_de_banda_sube_en_lineal():
    medio = costo_color(vivo(0), vivo(48.75))  # 18.75 grados de la banda analoga
    assert medio == pytest.approx(0.5)


def test_el_peor_matiz_cuesta_uno():
    assert costo_color(vivo(0), vivo(67.5)) == pytest.approx(1.0)


def test_el_costo_nunca_pasa_de_uno():
    assert costo_color(vivo(0), vivo(67.5), reglas=ReglasColor(grados_para_costo_maximo=5)) == 1.0


def test_el_matiz_circular_cuenta_como_analogo():
    assert costo_color(vivo(350), vivo(10)) == 0.0


@pytest.mark.parametrize(
    "neutro",
    [ColorLCh(80, 14.9, 200), ColorLCh(30, 29.9, 200)],
)
def test_neutros_cuestan_cero_frente_a_cualquier_color(neutro):
    assert costo_color(vivo(0), neutro) == 0.0
    assert costo_color(neutro, vivo(67.5)) == 0.0


def test_los_limites_de_neutro_no_son_inclusivos():
    assert costo_color(vivo(0), ColorLCh(80, 15, 67.5)) == pytest.approx(1.0)
    assert costo_color(vivo(0), ColorLCh(35, 29, 67.5)) == pytest.approx(1.0)
    assert costo_color(vivo(0), ColorLCh(30, 30, 67.5)) == pytest.approx(1.0)


def test_denim_es_neutro_aunque_tenga_croma():
    assert costo_color(vivo(0), vivo(67.5), textura_b=DENIM) == 0.0
    assert costo_color(vivo(0), vivo(67.5), textura_a=DENIM) == 0.0


def test_las_bandas_son_configurables():
    reglas = ReglasColor(analoga_max=60.0)
    assert costo_color(vivo(0), vivo(55), reglas=reglas) == 0.0
