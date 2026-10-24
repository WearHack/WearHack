import pytest

from app.motor.color import ColorLCh
from app.motor.estacion import estacion_activa
from app.motor.modelos import Formalidad, Prenda, Slot, Textura
from app.motor.mood import (
    W_MOOD,
    Mood,
    ReglasMood,
    costo_mood,
    costo_mood_ponderado,
    formalidad_normalizada,
)

F = Formalidad


def prenda(nivel=None, color=None, textura=None, slot=Slot.TORSO_SUPERIOR) -> Prenda:
    rango = (nivel, nivel) if nivel is not None else None
    return Prenda(id=f"{slot}-{nivel}", slot=slot, formalidad=rango, color=color, textura=textura)


GRIS = ColorLCh(luz=60, croma=5, matiz=0)
VIVO = ColorLCh(luz=60, croma=80, matiz=40)
EVENTO_CASUAL_A_FORMAL = (F.CASUAL, F.FORMAL)


def test_sin_mood_el_costo_y_el_peso_son_cero():
    outfit = (prenda(F.FORMAL, VIVO),)
    assert costo_mood(outfit, None) == 0.0
    assert costo_mood_ponderado(outfit, None) == 0.0


def test_el_peso_por_defecto_es_cero_coma_dos():
    assert W_MOOD == 0.2
    assert costo_mood_ponderado((prenda(F.FORMAL),), Mood.RELAJADO) == pytest.approx(0.2)


def test_formalidad_normalizada_dentro_del_rango_del_evento():
    # Media 2 en un evento CASUAL(1)..FORMAL(3): (2-1)/(3-1)
    outfit = (prenda(F.SMART_CASUAL), prenda(F.SMART_CASUAL))
    assert formalidad_normalizada(outfit, EVENTO_CASUAL_A_FORMAL) == pytest.approx(0.5)


def test_formalidad_se_limita_a_cero_y_uno():
    assert formalidad_normalizada((prenda(F.DEPORTIVO),), EVENTO_CASUAL_A_FORMAL) == 0.0
    assert formalidad_normalizada((prenda(F.FORMAL),), (F.DEPORTIVO, F.SMART_CASUAL)) == 1.0


def test_rango_de_prenda_cuenta_por_su_punto_medio():
    versatil = Prenda(id="v", slot=Slot.TORSO_SUPERIOR, formalidad=(F.CASUAL, F.SMART_CASUAL))
    assert formalidad_normalizada((versatil,), (F.DEPORTIVO, F.FORMAL)) == pytest.approx(0.5)


def test_accesorios_sin_formalidad_no_cuentan():
    sin_formalidad = prenda(slot=Slot.ACCESORIO_JOYERIA)
    outfit = (prenda(F.FORMAL), sin_formalidad)
    assert formalidad_normalizada(outfit, (F.DEPORTIVO, F.FORMAL)) == 1.0


def test_evento_de_un_solo_nivel_no_discrimina():
    outfit = (prenda(F.FORMAL),)
    assert costo_mood(outfit, Mood.RELAJADO, (F.FORMAL, F.FORMAL)) == 0.5
    assert costo_mood(outfit, Mood.ELEGANTE, (F.FORMAL, F.FORMAL)) == 0.5


def test_relajado_favorece_lo_menos_formal():
    informal, formal = (prenda(F.CASUAL),), (prenda(F.FORMAL),)
    assert costo_mood(informal, Mood.RELAJADO, EVENTO_CASUAL_A_FORMAL) == 0.0
    assert costo_mood(formal, Mood.RELAJADO, EVENTO_CASUAL_A_FORMAL) == 1.0


def test_elegante_favorece_lo_mas_formal():
    informal, formal = (prenda(F.CASUAL),), (prenda(F.FORMAL),)
    assert costo_mood(formal, Mood.ELEGANTE, EVENTO_CASUAL_A_FORMAL) == 0.0
    assert costo_mood(informal, Mood.ELEGANTE, EVENTO_CASUAL_A_FORMAL) == 1.0


def test_atrevido_cuesta_la_proporcion_de_neutras():
    outfit = (prenda(color=GRIS), prenda(color=GRIS), prenda(color=VIVO), prenda(color=VIVO))
    assert costo_mood(outfit, Mood.ATREVIDO) == pytest.approx(0.5)


def test_atrevido_cuenta_el_denim_como_neutro():
    outfit = (prenda(color=VIVO, textura=Textura.DENIM), prenda(color=VIVO))
    assert costo_mood(outfit, Mood.ATREVIDO) == pytest.approx(0.5)


def test_atrevido_prefiere_mas_color():
    assert costo_mood((prenda(color=VIVO),), Mood.ATREVIDO) < costo_mood(
        (prenda(color=GRIS),), Mood.ATREVIDO
    )


def test_discreto_cuesta_el_croma_medio_normalizado():
    outfit = (prenda(color=ColorLCh(60, 20, 0)), prenda(color=ColorLCh(60, 60, 0)))
    assert costo_mood(outfit, Mood.DISCRETO) == pytest.approx(0.4)


def test_discreto_prefiere_menos_croma_y_se_limita_a_uno():
    assert costo_mood((prenda(color=GRIS),), Mood.DISCRETO) < costo_mood(
        (prenda(color=VIVO),), Mood.DISCRETO
    )
    saturado = (prenda(color=ColorLCh(60, 300, 0)),)
    assert costo_mood(saturado, Mood.DISCRETO) == 1.0


@pytest.mark.parametrize("mood", [Mood.ATREVIDO, Mood.DISCRETO])
def test_sin_colores_conocidos_los_moods_de_color_cuestan_cero(mood):
    assert costo_mood((prenda(F.CASUAL),), mood) == 0.0


def test_los_umbrales_de_mood_son_configurables():
    reglas = ReglasMood(w_mood=0.5, croma_maximo=50.0)
    outfit = (prenda(color=ColorLCh(60, 25, 0)),)
    assert costo_mood(outfit, Mood.DISCRETO, reglas=reglas) == pytest.approx(0.5)
    assert costo_mood_ponderado(outfit, Mood.DISCRETO, reglas=reglas) == pytest.approx(0.25)


@pytest.mark.parametrize(
    ("latitud", "activa"),
    [
        (4.7, False),  # Bogota
        (6.2, False),  # Medellin
        (0.0, False),
        (23.5, False),  # el limite no cuenta
        (-23.5, False),
        (23.6, True),
        (-33.4, True),  # Santiago de Chile
        (40.4, True),  # Madrid
        (None, False),
    ],
)
def test_estacion_solo_se_activa_fuera_del_tropico(latitud, activa):
    assert estacion_activa(latitud) is activa
