"""Metricas y veredicto con mediciones fabricadas de resultado conocido.

Cuatro personas, una por grupo de tono salvo el 4-7 (dos), con las tres luces
normales y dos repeticiones. T0 se mueve con la luz; T1 no. El veredicto tiene
que elegir T1.
"""

import csv

import pytest

from normalizacion.analizar import analizar, informe, leer, m3, m6, ruido_repeticion, veredicto
from normalizacion.extraer import COLUMNAS

PERSONAS = {  # seudonimo: (monk, calidez, contraste, L de piel)
    "P1": (2, 5.0, 10.0, 70.0),
    "P2": (5, 10.0, 15.0, 60.0),
    "P3": (6, 30.0, 40.0, 50.0),
    "P4": (9, 40.0, 50.0, 35.0),
}
DESPLAZAMIENTO = {"VEN": 0.0, "LEDC": 15.0, "LEDF": -15.0}  # lo que mueve la luz sin corregir


def fila(seudonimo, luz, rep, tecnica, mover=0.0, motivo="", **extra):
    monk, calidez, contraste, L = PERSONAS[seudonimo]
    calidez += mover
    contraste += mover
    f = {c: "" for c in COLUMNAS}
    f.update(
        fuente="sesion", id=f"{seudonimo}_{luz}_D1_{rep}_N", seudonimo=seudonimo, luz=luz,
        celular="D1", repeticion=rep, tarjeta=0, monk=monk, tecnica=tecnica, motivo=motivo,
        luz_r=0.577, luz_g=0.577, luz_b=0.577,
        piel_L=L, piel_a=12.0, piel_b=calidez + 12.0, piel_n=500,
        cabello_L=L - contraste, cabello_a=5.0, cabello_b=8.0, cabello_n=300,
        ojos_L=25.0, ojos_a=5.0, ojos_b=6.0, ojos_n=40,
        piel_calidez=calidez, contraste=contraste,
        subtono="CALIDO" if calidez >= 20 else "FRIO",
        clase_contraste="ALTO" if contraste >= 27.5 else "BAJO",
        estacion="", quemados_pct=0.1, negros_pct=0.0, nitidez=120.0, ancho_rostro=400,
    )  # fmt: skip
    f.update(extra)
    return {k: ("" if v is None else v) for k, v in f.items()}


def sesion(tecnicas=("T0", "T1")):
    filas = []
    for s in PERSONAS:
        for luz, mover in DESPLAZAMIENTO.items():
            for i, rep in enumerate(("R2", "R3")):
                ruido = 0.3 * (-1) ** i
                for t in tecnicas:
                    filas.append(fila(s, luz, rep, t, mover=(mover if t == "T0" else 0.0) + ruido))
    return filas


def por_csv(filas, tmp_path):
    """Pasa por el CSV, como en la vida real: asi se prueban tambien los tipos."""
    ruta = tmp_path / "mediciones.csv"
    with ruta.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=COLUMNAS)
        w.writeheader()
        w.writerows(filas)
    return leer(ruta)


def test_elige_la_tecnica_estable_y_rechaza_la_que_se_mueve_con_la_luz(tmp_path):
    resultados = analizar(por_csv(sesion(), tmp_path), umbrales={})
    t0, t1 = resultados["tecnicas"]["T0"], resultados["tecnicas"]["T1"]

    assert t0["m2"]["mediana"]["subtono"]["tasa"] > 0.10
    assert t1["m2"]["mediana"]["subtono"]["tasa"] == 0
    assert t1["m2"]["centroides"]["subtono"]["tasa"] == 0
    assert t1["m1"]["piel"]["p90"] < t0["m1"]["piel"]["p90"]
    ver = resultados["veredicto"]
    assert ver["elegida"] == "T1"
    assert ver["tecnicas"]["T1"]["equidad"] is True
    assert ver["tecnicas"]["T1"]["secundario"] is True
    assert ver["tecnicas"]["T0"]["cumple"] is False
    assert set(t1["m5"]) == {"1-3", "4-7", "8-10"}
    assert "T1" in informe(resultados)


def test_ref_no_se_puede_elegir_aunque_sea_perfecta(tmp_path):
    filas = [f for f in sesion(("T0", "REF"))]
    ver = analizar(por_csv(filas, tmp_path), umbrales={})["veredicto"]
    assert ver["tecnicas"]["REF"]["cumple"] is True
    assert ver["elegida"] is None
    assert any("T3" in a for a in ver["avisos"])


def test_una_tecnica_que_falla_en_muchas_fotos_no_cumple(tmp_path):
    filas = sesion(("T0", "T1"))
    for i, f in enumerate(filas):
        if f["tecnica"] == "T1" and i % 4 == 1:
            f.update(motivo="sin_referencia", piel_calidez="", contraste="")
    resultados = analizar(por_csv(filas, tmp_path), umbrales={})
    assert resultados["tecnicas"]["T1"]["cobertura"] < 0.9
    assert resultados["veredicto"]["tecnicas"]["T1"]["cumple"] is False


def test_sin_grupos_de_tono_la_equidad_queda_sin_evaluar(tmp_path):
    filas = sesion()
    for f in filas:
        f["monk"] = ""
    ver = analizar(por_csv(filas, tmp_path), umbrales={})["veredicto"]
    assert ver["tecnicas"]["T1"]["equidad"] is None
    assert ver["elegida"] == "T1"
    assert any("provisional" in a for a in ver["avisos"])


def test_m3_compara_con_la_tarjeta(tmp_path):
    calida = {"ref_r": 0.70, "ref_g": 0.57, "ref_b": 0.43}
    filas = [
        fila("P1", "LEDC", "R1", "T0", **calida),
        fila("P1", "LEDC", "R1", "T1", luz_r=0.70, luz_g=0.57, luz_b=0.43, **calida),
    ]
    filas = por_csv(filas, tmp_path)
    assert m3(filas, "T0")["p50"] > 10  # suponer luz neutra se equivoca
    assert m3(filas, "T1")["p50"] == pytest.approx(0, abs=0.1)


def test_m6_cuenta_rechazos_por_luz_con_umbrales(tmp_path):
    filas = sesion(("T0",))
    for f in filas:
        if f["luz"] == "LEDC":
            f["quemados_pct"] = 5.0
    filas = por_csv(filas, tmp_path)
    con = m6(filas, {"max_quemados": 2.0})
    assert con["luz"]["LEDC"]["rechazo"] == 1.0
    assert con["luz"]["VEN"]["rechazo"] == 0.0
    assert m6(filas, {})["luz"]["VEN"]["rechazo"] is None


def test_ruido_de_repeticion_entre_r2_y_r3(tmp_path):
    filas = por_csv(sesion(("T1",)), tmp_path)
    ruido = ruido_repeticion(filas)
    assert ruido["n"] == len(PERSONAS) * 3
    assert 0 < ruido["p90"] < 2


def test_veredicto_sin_datos_no_revienta():
    vacio = {
        "cobertura": None,
        "m1": {"piel": {"p90": None}},
        "m2": {"mediana": {"subtono": {"tasa": None}, "contraste": {"tasa": None}}},
        "m5": {},
    }
    ver = veredicto({"T0": vacio})
    assert ver["elegida"] is None
    assert ver["tecnicas"]["T0"]["cumple"] is False
