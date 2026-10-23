import pytest

from app.motor.modelos import Clima, Patron, Prenda, Slot, Textura
from app.motor.reglas_duras import (
    cumple_reglas_duras,
    respeta_maximo_no_lisas,
    tiene_capa_para_frio,
)


def prenda(slot: Slot, patron: Patron = Patron.LISO, textura: Textura | None = None) -> Prenda:
    return Prenda(id=f"{slot}-{patron}-{textura}", slot=slot, patron=patron, textura=textura)


CAMISA = prenda(Slot.TORSO_SUPERIOR)
PANTALON = prenda(Slot.TORSO_INFERIOR)
ZAPATOS = prenda(Slot.CALZADO)


def test_todo_liso_cumple():
    assert respeta_maximo_no_lisas([CAMISA, PANTALON, ZAPATOS])


def test_una_no_lisa_cumple():
    assert respeta_maximo_no_lisas([prenda(Slot.TORSO_SUPERIOR, Patron.RAYAS), PANTALON])


def test_dos_no_lisas_no_cumplen():
    rayas = prenda(Slot.TORSO_SUPERIOR, Patron.RAYAS)
    floral = prenda(Slot.TORSO_INFERIOR, Patron.FLORAL)
    assert not respeta_maximo_no_lisas([rayas, floral, ZAPATOS])


def test_cualquier_patron_distinto_de_liso_cuenta():
    for patron in Patron:
        if patron == Patron.LISO:
            continue
        assert respeta_maximo_no_lisas([prenda(Slot.TORSO_SUPERIOR, patron)])
        assert not respeta_maximo_no_lisas(
            [prenda(Slot.TORSO_SUPERIOR, patron), prenda(Slot.TORSO_INFERIOR, patron)]
        )


def test_un_exterior_abriga():
    assert tiene_capa_para_frio([CAMISA, prenda(Slot.EXTERIOR)])


@pytest.mark.parametrize("textura", [Textura.PUNTO, Textura.ACOLCHADO])
def test_torso_superior_de_punto_o_acolchado_abriga(textura):
    assert tiene_capa_para_frio([prenda(Slot.TORSO_SUPERIOR, textura=textura), PANTALON])


@pytest.mark.parametrize("textura", [None, Textura.LINO, Textura.DENIM, Textura.PANO])
def test_torso_superior_de_otra_textura_no_abriga(textura):
    assert not tiene_capa_para_frio([prenda(Slot.TORSO_SUPERIOR, textura=textura), PANTALON])


def test_punto_en_otro_slot_no_abriga():
    assert not tiene_capa_para_frio([prenda(Slot.TORSO_INFERIOR, textura=Textura.PUNTO)])


def test_frio_sin_capa_se_descarta():
    assert not cumple_reglas_duras((CAMISA, PANTALON, ZAPATOS), Clima.FRIO)


def test_frio_con_capa_cumple():
    assert cumple_reglas_duras((CAMISA, PANTALON, prenda(Slot.EXTERIOR)), Clima.FRIO)


@pytest.mark.parametrize("clima", [Clima.TEMPLADO, Clima.CALIDO, None])
def test_fuera_del_frio_no_se_exige_capa(clima):
    assert cumple_reglas_duras((CAMISA, PANTALON, ZAPATOS), clima)


def test_las_dos_reglas_se_aplican_juntas():
    rayas = prenda(Slot.TORSO_SUPERIOR, Patron.RAYAS)
    floral = prenda(Slot.TORSO_INFERIOR, Patron.FLORAL)
    assert not cumple_reglas_duras((rayas, floral, prenda(Slot.EXTERIOR)), Clima.FRIO)
