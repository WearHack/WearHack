import pytest

from app.motor.color import ColorLCh
from app.motor.costos import (
    Componentes,
    Estacion,
    PerfilColor,
    Pesos,
    TablaTexturas,
    c_color,
    c_formalidad,
    c_paleta,
    c_paleta_prenda,
    c_textura,
    componentes,
    es_calido,
)
from app.motor.modelos import Formalidad, Prenda, Slot, Textura
from app.motor.mood import Mood

F = Formalidad
ROJO = ColorLCh(luz=50, croma=70, matiz=40)  # calido
AZUL = ColorLCh(luz=50, croma=70, matiz=260)  # frio
GRIS = ColorLCh(luz=60, croma=5, matiz=0)

CALIDO_PURO = PerfilColor({Estacion.OTONO: 1.0})  # calido, contraste alto
FRIO_SUAVE = PerfilColor({Estacion.VERANO: 1.0})  # frio, contraste bajo


def prenda(id="p", slot=Slot.TORSO_SUPERIOR, color=None, formalidad=None, textura=None):
    return Prenda(id=id, slot=slot, color=color, formalidad=formalidad, textura=textura)


def test_pesos_iniciales_de_la_spec():
    assert Pesos() == Pesos(color=0.35, paleta=0.25, formalidad=0.25, textura=0.15)


def test_c_color_promedia_los_pares_con_color():
    # ROJO-ROJO analogo (0), ROJO-ROJO (0), ROJO-sin color no cuenta
    outfit = (prenda("a", color=ROJO), prenda("b", color=ROJO), prenda("c"))
    assert c_color(outfit) == 0.0
    # rojo (40) con un matiz a 67.5 grados: el peor caso, costo 1
    lejano = ColorLCh(luz=50, croma=70, matiz=107.5)
    assert c_color((prenda("a", color=ROJO), prenda("b", color=lejano))) == pytest.approx(1.0)


def test_c_color_sin_pares_es_cero():
    assert c_color((prenda(color=ROJO),)) == 0.0


@pytest.mark.parametrize(
    ("a", "b", "esperado"),
    [
        ((F.CASUAL, F.SMART_CASUAL), (F.SMART_CASUAL, F.FORMAL), 0.0),  # se cruzan
        ((F.DEPORTIVO, F.DEPORTIVO), (F.FORMAL, F.FORMAL), 1.0),  # 3 niveles
        ((F.CASUAL, F.CASUAL), (F.FORMAL, F.FORMAL), 2 / 3),
        ((F.FORMAL, F.FORMAL), (F.CASUAL, F.CASUAL), 2 / 3),  # simetrico
    ],
)
def test_c_formalidad_por_niveles(a, b, esperado):
    outfit = (prenda("a", formalidad=a), prenda("b", formalidad=b))
    assert c_formalidad(outfit) == pytest.approx(esperado)


def test_c_formalidad_ignora_las_neutras():
    outfit = (prenda("a", formalidad=(F.FORMAL, F.FORMAL)), prenda("b"))
    assert c_formalidad(outfit) == 0.0


def test_c_textura_arranca_en_cero_coma_cinco():
    outfit = (prenda("a", textura=Textura.DENIM), prenda("b", textura=Textura.CUERO))
    assert c_textura(outfit) == pytest.approx(0.5)


def test_c_textura_aprende_de_la_tabla():
    par = frozenset({Textura.DENIM, Textura.CUERO})
    tabla = TablaTexturas(positivos={par: 5})  # q = 5/10 -> C = 0.25
    outfit = (prenda("a", textura=Textura.DENIM), prenda("b", textura=Textura.CUERO))
    assert c_textura(outfit, tabla) == pytest.approx(0.25)
    tabla_mala = TablaTexturas(negativos={par: 5})  # q = -0.5 -> C = 0.75
    assert c_textura(outfit, tabla_mala) == pytest.approx(0.75)


@pytest.mark.parametrize(("matiz", "calido"), [(40, True), (90, True), (260, False), (0, False)])
def test_corte_entre_calidos_y_frios(matiz, calido):
    assert es_calido(matiz) is calido


def test_c_paleta_castiga_la_temperatura_contraria():
    assert c_paleta_prenda(prenda(color=ROJO), CALIDO_PURO) == 0.0
    assert c_paleta_prenda(prenda(color=AZUL), CALIDO_PURO) == pytest.approx(0.5)


def test_c_paleta_castiga_el_croma_alto_en_contraste_bajo():
    muy_vivo_frio = ColorLCh(luz=50, croma=100, matiz=260)
    # Frio y contraste bajo: la temperatura no castiga, el croma si (al tope).
    assert c_paleta_prenda(prenda(color=muy_vivo_frio), FRIO_SUAVE) == pytest.approx(0.5)
    suave_frio = ColorLCh(luz=50, croma=40, matiz=260)
    assert c_paleta_prenda(prenda(color=suave_frio), FRIO_SUAVE) == 0.0


def test_c_paleta_solo_mira_lo_que_esta_cerca_de_la_cara():
    pantalon = prenda(slot=Slot.TORSO_INFERIOR, color=AZUL)
    assert c_paleta_prenda(pantalon, CALIDO_PURO) == 0.0
    bufanda = prenda(slot=Slot.ACCESORIO_CUELLO, color=AZUL)
    assert c_paleta_prenda(bufanda, CALIDO_PURO) > 0


def test_c_paleta_los_neutros_cuestan_cero():
    assert c_paleta_prenda(prenda(color=GRIS), CALIDO_PURO) == 0.0


def test_c_paleta_sin_perfil_es_cero():
    assert c_paleta((prenda(color=AZUL),), None) == 0.0


def test_c_paleta_promedia_las_prendas_de_la_cara():
    outfit = (
        prenda("a", color=ROJO),
        prenda("b", slot=Slot.EXTERIOR, color=AZUL),
        prenda("c", slot=Slot.TORSO_INFERIOR, color=AZUL),
    )
    assert c_paleta(outfit, CALIDO_PURO) == pytest.approx(0.25)


def test_total_pondera_cada_componente():
    partes = Componentes(color=1, paleta=1, formalidad=1, textura=1, mood=1)
    assert partes.total(Pesos(), w_mood=0.2) == pytest.approx(1.2)
    assert partes.total(Pesos(), w_mood=0.0) == pytest.approx(1.0)


def test_componentes_junta_todo():
    outfit = (
        prenda("a", color=AZUL, formalidad=(F.FORMAL, F.FORMAL)),
        prenda("b", slot=Slot.TORSO_INFERIOR, formalidad=(F.CASUAL, F.CASUAL)),
    )
    partes = componentes(outfit, CALIDO_PURO, Mood.ELEGANTE, (F.CASUAL, F.FORMAL))
    assert partes.formalidad == pytest.approx(2 / 3)
    assert partes.paleta == pytest.approx(0.5)
    assert partes.mood == pytest.approx(0.5)  # media 2 en CASUAL..FORMAL
