import pytest

from app.motor.color import ColorLCh
from app.motor.costos import Estacion, PerfilColor, Pesos
from app.motor.modelos import Clima, Formalidad, Patron, Prenda, Slot, Textura
from app.motor.motor import (
    Contexto,
    ReglasMotor,
    RepositorioPesosEnMemoria,
    completar,
    elegir_anclas,
    funcion_costo,
    pesos_para,
    puntuar,
    recomendar,
    recomendar_para_usuario,
)
from app.motor.mood import Mood
from app.motor.puente import evaluar_candidata

F = Formalidad
PERFIL = PerfilColor({Estacion.OTONO: 1.0})


def color(matiz, croma=60):
    return ColorLCh(luz=50, croma=croma, matiz=matiz)


def prenda(id, slot, matiz=None, **kw):
    return Prenda(id=id, slot=slot, color=color(matiz) if matiz is not None else None, **kw)


def closet_basico():
    # Matices escogidos para que algunas combinaciones sean claramente peores.
    return [
        prenda("ts_rojo", Slot.TORSO_SUPERIOR, 40),
        prenda("ts_naranja", Slot.TORSO_SUPERIOR, 60),
        prenda("ts_verde", Slot.TORSO_SUPERIOR, 140),
        prenda("ti_rojo", Slot.TORSO_INFERIOR, 30),
        prenda("ti_verde", Slot.TORSO_INFERIOR, 150),
        prenda("ti_morado", Slot.TORSO_INFERIOR, 300),
        prenda("cz_rojo", Slot.CALZADO, 45),
        prenda("cz_verde", Slot.CALZADO, 145),
    ]


def ids(outfit):
    return {p.id for p in outfit}


# --------------------------------------------------------------- pesos ---


def test_sin_pesos_personales_usa_los_iniciales():
    repo = RepositorioPesosEnMemoria()
    assert pesos_para("ana", repo, PERFIL) == Pesos()


def test_con_pesos_personales_usa_los_del_usuario():
    propios = Pesos(color=0.5, paleta=0.2, formalidad=0.2, textura=0.1)
    repo = RepositorioPesosEnMemoria(personales={"ana": propios})
    assert pesos_para("ana", repo, PERFIL) == propios
    assert pesos_para("otro", repo, PERFIL) == Pesos()


def test_sin_perfil_de_color_w_paleta_es_cero():
    repo = RepositorioPesosEnMemoria()
    assert pesos_para("ana", repo, None).paleta == 0.0
    assert pesos_para("ana", repo, None).color == 0.35


# --------------------------------------------------------------- costo ---


def test_puntuar_suma_mood_solo_si_hay_mood():
    outfit = (prenda("a", Slot.TORSO_SUPERIOR, formalidad=(F.FORMAL, F.FORMAL)),)
    sin = puntuar(outfit, Contexto(), Pesos())
    con = puntuar(outfit, Contexto(mood=Mood.RELAJADO), Pesos())
    assert sin.costo == 0.0
    assert con.costo == pytest.approx(0.2)  # RELAJADO con todo FORMAL: C_mood 1


# --------------------------------------------------------------- anclas ---


def test_las_anclas_alternan_slots():
    closet = closet_basico() + [prenda("vestido", Slot.CUERPO_COMPLETO, 40)]
    anclas = elegir_anclas(closet, 5)
    assert [a.id for a in anclas] == ["ts_rojo", "ti_rojo", "vestido", "ts_naranja", "ti_verde"]


def test_las_anclas_no_pasan_de_n_ni_incluyen_calzado():
    anclas = elegir_anclas(closet_basico(), 10)
    assert len(anclas) == 6
    assert all(a.slot != Slot.CALZADO for a in anclas)


# ----------------------------------------------------------- completar ---


def test_completar_escoge_lo_que_mejor_combina():
    closet = closet_basico()
    por_slot = {}
    for p in closet:
        por_slot.setdefault(p.slot, []).append(p)
    costo = funcion_costo(Contexto(), Pesos())
    outfit = completar(closet[0], por_slot, costo, None)  # ancla: ts_rojo
    assert ids(outfit) == {"ts_rojo", "ti_rojo", "cz_rojo"}


def test_completar_falla_sin_un_slot_obligatorio():
    torso = prenda("ts", Slot.TORSO_SUPERIOR, 40)
    por_slot = {Slot.TORSO_INFERIOR: [prenda("ti", Slot.TORSO_INFERIOR, 40)]}
    assert completar(torso, por_slot, funcion_costo(Contexto(), Pesos()), None) is None


def test_completar_respeta_maximo_una_no_lisa():
    rayas = Prenda(id="rayas", slot=Slot.TORSO_SUPERIOR, patron=Patron.RAYAS, color=color(40))
    floral = Prenda(id="floral", slot=Slot.TORSO_INFERIOR, patron=Patron.FLORAL, color=color(40))
    liso = prenda("liso", Slot.TORSO_INFERIOR, 140)
    zapatos = prenda("zap", Slot.CALZADO, 40)
    por_slot = {Slot.TORSO_INFERIOR: [floral, liso], Slot.CALZADO: [zapatos]}
    outfit = completar(rayas, por_slot, funcion_costo(Contexto(), Pesos()), None)
    assert ids(outfit) == {"rayas", "liso", "zap"}


def test_completar_en_frio_obliga_a_poner_exterior():
    torso = prenda("ts", Slot.TORSO_SUPERIOR, 40)
    # 67.5 grados de todo lo demas: el peor matiz. Solo entra si la regla lo obliga.
    abrigo = prenda("abrigo", Slot.EXTERIOR, 107.5)
    por_slot = {
        Slot.TORSO_INFERIOR: [prenda("ti", Slot.TORSO_INFERIOR, 40)],
        Slot.CALZADO: [prenda("zap", Slot.CALZADO, 40)],
        Slot.EXTERIOR: [abrigo],
    }
    costo = funcion_costo(Contexto(), Pesos())
    assert "abrigo" not in ids(completar(torso, por_slot, costo, Clima.TEMPLADO))
    assert "abrigo" in ids(completar(torso, por_slot, costo, Clima.FRIO))


def test_completar_en_frio_sin_capa_posible_no_da_outfit():
    torso = prenda("ts", Slot.TORSO_SUPERIOR, 40)
    por_slot = {
        Slot.TORSO_INFERIOR: [prenda("ti", Slot.TORSO_INFERIOR, 40)],
        Slot.CALZADO: [prenda("zap", Slot.CALZADO, 40)],
    }
    assert completar(torso, por_slot, funcion_costo(Contexto(), Pesos()), Clima.FRIO) is None


def test_un_torso_de_punto_basta_como_capa():
    punto = Prenda(id="punto", slot=Slot.TORSO_SUPERIOR, textura=Textura.PUNTO)
    por_slot = {
        Slot.TORSO_INFERIOR: [prenda("ti", Slot.TORSO_INFERIOR)],
        Slot.CALZADO: [prenda("zap", Slot.CALZADO)],
    }
    outfit = completar(punto, por_slot, funcion_costo(Contexto(), Pesos()), Clima.FRIO)
    assert ids(outfit) == {"punto", "ti", "zap"}


# ---------------------------------------------------------- recomendar ---


def test_devuelve_tres_outfits_distintos_ordenados_por_costo():
    resultado = recomendar(closet_basico(), Contexto(), Pesos())
    assert len(resultado) == 3
    costos = [o.costo for o in resultado]
    assert costos == sorted(costos)
    for i, a in enumerate(resultado):
        for b in resultado[i + 1 :]:
            assert len(ids(a.prendas) ^ ids(b.prendas)) >= 2


def test_cada_par_de_outfits_difiere_en_al_menos_dos_prendas_principales():
    resultado = recomendar(closet_basico(), Contexto(), Pesos())
    for i, a in enumerate(resultado):
        for b in resultado[i + 1 :]:
            assert len(ids(a.prendas) - ids(b.prendas)) >= 2


def test_el_mejor_va_primero():
    # Rojos entre si (analogos) o naranja-morado-rojo (triada) cuestan 0; el
    # verde con el rojo, no. El primero tiene que ser uno de costo 0.
    resultado = recomendar(closet_basico(), Contexto(), Pesos())
    assert resultado[0].costo == 0.0
    assert "ts_verde" not in ids(resultado[0].prendas)


def test_en_empate_de_costo_el_orden_es_estable():
    resultado = recomendar(closet_basico(), Contexto(), Pesos())
    empatados = [o for o in resultado if o.costo == resultado[0].costo]
    claves = [sorted(ids(o.prendas)) for o in empatados]
    assert claves == sorted(claves)


def test_con_un_closet_pequeno_devuelve_menos_de_tres():
    closet = [
        prenda("ts", Slot.TORSO_SUPERIOR, 40),
        prenda("ti", Slot.TORSO_INFERIOR, 40),
        prenda("cz", Slot.CALZADO, 40),
    ]
    assert len(recomendar(closet, Contexto(), Pesos())) == 1


def test_closet_vacio_no_da_outfits():
    assert recomendar([], Contexto(), Pesos()) == []


def test_aplica_el_filtro_de_clima():
    closet = closet_basico()
    closet[0] = Prenda(
        id="ts_rojo",
        slot=Slot.TORSO_SUPERIOR,
        color=color(40),
        clima_apto=frozenset({Clima.CALIDO}),
    )
    resultado = recomendar(closet, Contexto(clima=Clima.TEMPLADO), Pesos())
    assert all("ts_rojo" not in ids(o.prendas) for o in resultado)


def test_aplica_el_dress_code():
    closet = [
        prenda("ts_formal", Slot.TORSO_SUPERIOR, 40, formalidad=(F.FORMAL, F.FORMAL)),
        prenda("ts_casual", Slot.TORSO_SUPERIOR, 40, formalidad=(F.CASUAL, F.CASUAL)),
        prenda("ti", Slot.TORSO_INFERIOR, 40, formalidad=(F.CASUAL, F.FORMAL)),
        prenda("cz", Slot.CALZADO, 40),
    ]
    resultado = recomendar(closet, Contexto(rango_evento=(F.FORMAL, F.FORMAL)), Pesos())
    assert [ids(o.prendas) for o in resultado] == [{"ts_formal", "ti", "cz"}]


def test_los_accesorios_no_entran_al_outfit():
    closet = closet_basico() + [prenda("reloj", Slot.ACCESORIO_RELOJ, 40)]
    for outfit in recomendar(closet, Contexto(), Pesos()):
        assert "reloj" not in ids(outfit.prendas)


def test_los_pesos_cambian_el_resultado():
    # Con solo formalidad, el color deja de importar y gana lo coherente en formalidad.
    closet = [
        prenda("ts", Slot.TORSO_SUPERIOR, 40, formalidad=(F.FORMAL, F.FORMAL)),
        prenda("ti_rojo_casual", Slot.TORSO_INFERIOR, 40, formalidad=(F.DEPORTIVO, F.DEPORTIVO)),
        prenda("ti_verde_formal", Slot.TORSO_INFERIOR, 150, formalidad=(F.FORMAL, F.FORMAL)),
        prenda("cz", Slot.CALZADO),
    ]
    solo_color = Pesos(color=1, paleta=0, formalidad=0, textura=0)
    solo_formalidad = Pesos(color=0, paleta=0, formalidad=1, textura=0)
    assert "ti_rojo_casual" in ids(recomendar(closet, Contexto(), solo_color)[0].prendas)
    assert "ti_verde_formal" in ids(recomendar(closet, Contexto(), solo_formalidad)[0].prendas)


def test_n_outfits_es_configurable():
    resultado = recomendar(closet_basico(), Contexto(), Pesos(), ReglasMotor(n_outfits=2))
    assert len(resultado) == 2


def test_es_determinista():
    a = recomendar(closet_basico(), Contexto(), Pesos())
    b = recomendar(closet_basico(), Contexto(), Pesos())
    assert [ids(o.prendas) for o in a] == [ids(o.prendas) for o in b]


def test_recomendar_para_usuario_lee_sus_pesos():
    repo = RepositorioPesosEnMemoria()
    resultado = recomendar_para_usuario("ana", closet_basico(), Contexto(), repo)
    assert resultado == recomendar(closet_basico(), Contexto(), Pesos(paleta=0.0))


def test_devuelve_los_componentes_por_separado():
    mejor = recomendar(closet_basico(), Contexto(perfil=PERFIL), Pesos())[0]
    assert mejor.componentes.color == 0.0
    assert mejor.costo == pytest.approx(mejor.componentes.total(Pesos(), 0.0))


# ------------------------------------------------------ prenda puente ---


def test_la_funcion_de_costo_sirve_para_la_prenda_puente():
    closet = closet_basico()
    costo = funcion_costo(Contexto(), Pesos())
    actuales = [o.prendas for o in recomendar(closet, Contexto(), Pesos())]
    candidata = prenda("ti_naranja", Slot.TORSO_INFERIOR, 50)
    resultado = evaluar_candidata(candidata, closet, actuales, costo, eventos={})
    assert resultado.combinaciones_buenas > 0
