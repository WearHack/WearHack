from app.motor.modelos import Clima, Formalidad, Patron, Prenda, Slot, Textura
from app.motor.puente import (
    ReglasPuente,
    eventos_habilitados,
    evaluar_candidata,
    generar_outfits,
    pasa_dress_code,
    rankear_puentes,
)

F = Formalidad
EVENTOS = {"DEPORTE": (F.DEPORTIVO, F.DEPORTIVO), "OFICINA": (F.SMART_CASUAL, F.FORMAL)}


def prenda(id, slot, patron=Patron.LISO, formalidad=None, textura=None) -> Prenda:
    return Prenda(id=id, slot=slot, patron=patron, formalidad=formalidad, textura=textura)


def superiores(n):
    return [prenda(f"ts{i}", Slot.TORSO_SUPERIOR) for i in range(n)]


def plano(_outfit):
    return 0.0


CANDIDATA = prenda("pantalon", Slot.TORSO_INFERIOR)
ZAPATOS = prenda("zapatos", Slot.CALZADO)
REFERENCIA = (prenda("ref", Slot.TORSO_SUPERIOR),)  # cuesta 0 con `plano`


def test_genera_el_producto_de_los_slots_del_closet():
    closet = [*superiores(3), ZAPATOS, prenda("tenis", Slot.CALZADO)]
    assert len(list(generar_outfits(CANDIDATA, closet))) == 6


def test_el_exterior_es_opcional():
    closet = [*superiores(3), ZAPATOS, prenda("abrigo", Slot.EXTERIOR)]
    # 3 superiores x 1 calzado x (sin exterior o con el abrigo)
    assert len(list(generar_outfits(CANDIDATA, closet))) == 6


def test_todos_los_outfits_llevan_la_candidata():
    closet = [*superiores(3), ZAPATOS]
    assert all(CANDIDATA in o for o in generar_outfits(CANDIDATA, closet))


def test_un_accesorio_no_genera_outfits():
    reloj = prenda("reloj", Slot.ACCESORIO_RELOJ)
    assert list(generar_outfits(reloj, [*superiores(3), ZAPATOS])) == []


def test_los_accesorios_del_closet_no_entran():
    closet = [*superiores(2), ZAPATOS, prenda("reloj", Slot.ACCESORIO_RELOJ)]
    assert all(len(o) == 3 for o in generar_outfits(CANDIDATA, closet))


def test_sin_calzado_no_hay_outfits():
    assert list(generar_outfits(CANDIDATA, superiores(5))) == []


def test_cuerpo_completo_no_se_mezcla_con_torsos():
    vestido = prenda("vestido", Slot.CUERPO_COMPLETO)
    closet = [*superiores(3), prenda("tenis", Slot.CALZADO), ZAPATOS]
    outfits = list(generar_outfits(vestido, closet))
    assert len(outfits) == 2
    assert all(vestido in o and len(o) == 2 for o in outfits)


def test_un_cuerpo_completo_del_closet_tambien_forma_outfits():
    closet = [prenda("vestido", Slot.CUERPO_COMPLETO), ZAPATOS]
    nuevo_calzado = prenda("tacones", Slot.CALZADO)
    assert len(list(generar_outfits(nuevo_calzado, closet))) == 1


def test_la_candidata_repetida_en_el_closet_no_se_cuenta_dos_veces():
    closet = [*superiores(2), ZAPATOS, CANDIDATA]
    assert len(list(generar_outfits(CANDIDATA, closet))) == 2


def evaluar(closet, actuales=(REFERENCIA,), costo=plano, candidata=CANDIDATA, **kw):
    return evaluar_candidata(candidata, closet, actuales, costo, EVENTOS, **kw)


def test_cinco_combinaciones_buenas_recomiendan():
    resultado = evaluar([*superiores(5), ZAPATOS])
    assert resultado.combinaciones_buenas == 5
    assert resultado.recomendada


def test_cuatro_combinaciones_buenas_no_recomiendan():
    resultado = evaluar([*superiores(4), ZAPATOS])
    assert resultado.combinaciones_buenas == 4
    assert not resultado.recomendada


def test_el_umbral_es_configurable():
    resultado = evaluar([*superiores(2), ZAPATOS], reglas=ReglasPuente(umbral=2))
    assert resultado.recomendada


def test_buena_es_costo_menor_o_igual_a_la_mediana():
    costos = {"ref1": 1.0, "ref2": 2.0, "ref3": 3.0}  # mediana 2.0
    actuales = [(prenda(k, Slot.TORSO_SUPERIOR),) for k in costos]
    por_superior = {"ts0": 0.5, "ts1": 2.0, "ts2": 2.1, "ts3": 9.0}

    def costo(outfit):
        return sum(costos.get(p.id, por_superior.get(p.id, 0.0)) for p in outfit)

    resultado = evaluar([*superiores(4), ZAPATOS], actuales=actuales, costo=costo)
    assert resultado.combinaciones_buenas == 2  # ts0 y ts1 (2.0 empata con la mediana)


def test_sin_outfits_de_referencia_todo_outfit_valido_es_bueno():
    resultado = evaluar([*superiores(5), ZAPATOS], actuales=(), costo=lambda o: 99.0)
    assert resultado.combinaciones_buenas == 5


def test_los_filtros_duros_descartan_combinaciones():
    rayada = prenda("rayada", Slot.TORSO_INFERIOR, Patron.RAYAS)
    floral = prenda("floral", Slot.TORSO_SUPERIOR, Patron.FLORAL)
    closet = [floral, *superiores(2), ZAPATOS]
    assert evaluar(closet, candidata=rayada).combinaciones_buenas == 2


def test_con_frio_solo_cuentan_los_outfits_con_capa():
    abrigo = prenda("abrigo", Slot.EXTERIOR)
    punto = prenda("punto", Slot.TORSO_SUPERIOR, textura=Textura.PUNTO)
    closet = [*superiores(3), punto, ZAPATOS, abrigo]
    # Con el abrigo: 4 superiores. Sin el, solo el de punto.
    assert evaluar(closet, clima=Clima.FRIO).combinaciones_buenas == 5
    assert evaluar(closet, clima=Clima.TEMPLADO).combinaciones_buenas == 8


def test_dress_code_cruza_rangos_y_las_prendas_sin_formalidad_pasan():
    versatil = prenda("v", Slot.TORSO_SUPERIOR, formalidad=(F.CASUAL, F.SMART_CASUAL))
    assert pasa_dress_code(versatil, (F.SMART_CASUAL, F.FORMAL))
    assert not pasa_dress_code(versatil, (F.FORMAL, F.FORMAL))
    assert pasa_dress_code(prenda("n", Slot.ACCESORIO_JOYERIA), (F.FORMAL, F.FORMAL))


def test_un_evento_se_habilita_si_todas_las_prendas_pasan():
    formal = prenda("f", Slot.TORSO_SUPERIOR, formalidad=(F.FORMAL, F.FORMAL))
    deportiva = prenda("d", Slot.TORSO_INFERIOR, formalidad=(F.DEPORTIVO, F.DEPORTIVO))
    assert eventos_habilitados((formal, ZAPATOS), EVENTOS) == {"OFICINA"}
    assert eventos_habilitados((formal, deportiva), EVENTOS) == frozenset()


def formal(id):
    return prenda(id, Slot.TORSO_INFERIOR, formalidad=(F.FORMAL, F.FORMAL))


def deportiva(id):
    return prenda(id, Slot.TORSO_INFERIOR, formalidad=(F.DEPORTIVO, F.DEPORTIVO))


# Hoy el usuario solo cubre DEPORTE.
SOLO_DEPORTE = ((prenda("dep", Slot.TORSO_SUPERIOR, formalidad=(F.DEPORTIVO, F.DEPORTIVO)),),)


def rankear(candidatas, closet=None, costo=plano, **kw):
    closet = closet or [*superiores(5), ZAPATOS]
    return rankear_puentes(candidatas, closet, SOLO_DEPORTE, costo, EVENTOS, **kw)


def test_el_ranking_descarta_lo_que_no_es_puente():
    pocas = [*superiores(2), ZAPATOS]
    assert rankear([CANDIDATA], closet=pocas) == []


def test_el_ranking_ordena_por_combinaciones_buenas():
    closet = [*superiores(5), ZAPATOS, prenda("tenis", Slot.CALZADO)]
    cuesta_poco, cuesta_mucho = prenda("a_poco", Slot.TORSO_INFERIOR), formal("b_mucho")

    def costo(outfit):
        return 5.0 if any(p.id == "b_mucho" for p in outfit) else 0.0

    # Mediana de la referencia: 0. "b_mucho" cuesta 5 en cada outfit, asi que no
    # abre ninguna combinacion buena y queda fuera del ranking.
    resultado = rankear([cuesta_mucho, cuesta_poco], closet=closet, costo=costo)
    assert [e.candidata.id for e in resultado] == ["a_poco"]
    assert resultado[0].combinaciones_buenas == 10


def test_un_exterior_sin_torso_inferior_en_el_closet_no_es_puente():
    closet = [*superiores(5), ZAPATOS, prenda("tenis", Slot.CALZADO)]
    exterior = prenda("chaqueta", Slot.EXTERIOR)
    assert rankear([exterior], closet=closet) == []


def test_primer_desempate_eventos_nuevos_que_hoy_no_cubre():
    nueva = formal("a_formal")  # habilita OFICINA, que hoy no cubre
    repetida = deportiva("b_deportiva")  # solo DEPORTE, ya cubierto
    resultado = rankear([repetida, nueva])
    assert [e.candidata.id for e in resultado] == ["a_formal", "b_deportiva"]
    assert [e.eventos_nuevos for e in resultado] == [1, 0]


def test_segundo_desempate_menor_costo_medio():
    barata, cara = formal("barata"), formal("cara")

    def costo(outfit):
        if any(p.id == "dep" for p in outfit):
            return 0.9  # la referencia fija la mediana en 0.9
        return 0.1 if any(p.id == "barata" for p in outfit) else 0.9

    resultado = rankear([cara, barata], costo=costo)
    assert [e.candidata.id for e in resultado] == ["barata", "cara"]
    assert resultado[0].costo_medio < resultado[1].costo_medio


def test_tercer_desempate_menor_c_paleta():
    a, b = formal("a"), formal("b")
    paleta = {"a": 0.8, "b": 0.2}.__getitem__
    resultado = rankear([a, b], costo_paleta=lambda p: paleta(p.id))
    assert [e.candidata.id for e in resultado] == ["b", "a"]
    assert [e.costo_paleta for e in resultado] == [0.2, 0.8]


def test_mas_combinaciones_gana_aunque_pierda_en_los_desempates():
    closet = [*superiores(5), ZAPATOS, prenda("tenis", Slot.CALZADO)]

    # Mediana de referencia: 1.0. Los outfits de la formal con los tenis cuestan 2.0
    # y no cuentan: la formal abre 5 de 10 y la deportiva los 10.
    def costo(outfit):
        ids = {p.id for p in outfit}
        return 2.0 if {"b_formal", "tenis"} <= ids else 1.0

    resultado = rankear([formal("b_formal"), deportiva("a_deportiva")], closet=closet, costo=costo)
    assert [e.candidata.id for e in resultado] == ["a_deportiva", "b_formal"]
    assert [e.combinaciones_buenas for e in resultado] == [10, 5]
    assert [e.eventos_nuevos for e in resultado] == [0, 1]
