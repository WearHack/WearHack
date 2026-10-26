from app.motor.filtros import filtrar_por_contexto, pasa_clima, pasa_dress_code
from app.motor.modelos import Clima, Formalidad, Prenda, Slot

F = Formalidad

SHORT = Prenda(
    id="short",
    slot=Slot.TORSO_INFERIOR,
    formalidad=(F.CASUAL, F.CASUAL),
    clima_apto=frozenset({Clima.TEMPLADO, Clima.CALIDO}),
)
ABRIGO = Prenda(
    id="abrigo",
    slot=Slot.EXTERIOR,
    formalidad=(F.SMART_CASUAL, F.FORMAL),
    clima_apto=frozenset({Clima.FRIO}),
)
RELOJ = Prenda(id="reloj", slot=Slot.ACCESORIO_RELOJ)


def test_clima_apto():
    assert pasa_clima(SHORT, Clima.CALIDO)
    assert not pasa_clima(SHORT, Clima.FRIO)


def test_sin_clima_todo_pasa():
    assert pasa_clima(ABRIGO, None)


def test_por_defecto_una_prenda_sirve_en_cualquier_clima():
    assert all(pasa_clima(RELOJ, c) for c in Clima)


def test_dress_code_sin_evento_todo_pasa():
    assert pasa_dress_code(SHORT, None)


def test_filtrar_por_contexto_aplica_los_dos():
    closet = [SHORT, ABRIGO, RELOJ]
    assert filtrar_por_contexto(closet, Clima.FRIO, (F.FORMAL, F.FORMAL)) == [ABRIGO, RELOJ]
    assert filtrar_por_contexto(closet, Clima.CALIDO, (F.CASUAL, F.CASUAL)) == [SHORT, RELOJ]
    assert filtrar_por_contexto(closet, None, None) == closet
