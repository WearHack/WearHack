"""Job de recalibracion de centroides (#37), con el artefacto de juguete de `falsos.py`.

En el artefacto, la capa de subtono usa solo `piel_calidez` (media 0, desviacion
5) y la de contraste solo `contraste`. CALIDO esta en z = 1 y FRIO en z = -1.
"""

import json
from datetime import UTC, datetime, timedelta

import pytest

from app.centroides import RepositorioCentroides
from app.jobs.recalibrar_centroides import (
    MIN_CORRECCIONES_POR_ESTACION,
    estacion_de,
    leer_conjunto,
    recalibrar_en,
    variables_de_piel,
    variables_medidas,
    version_recalibrada,
)
from tests import falsos

AHORA = datetime(2026, 10, 30, 3, 0, tzinfo=UTC)


class ColeccionSimple:
    """Correcciones y recalibraciones: find con igualdad o $exists, e insert sin _id."""

    def __init__(self, *documentos: dict) -> None:
        self.documentos = [dict(d) for d in documentos]

    def find(self, filtro: dict) -> list[dict]:
        def cumple(d):
            for clave, valor in filtro.items():
                if isinstance(valor, dict) and "$exists" in valor:
                    if (clave in d) != valor["$exists"]:
                        return False
                elif d.get(clave) != valor:
                    return False
            return True

        return [dict(d) for d in self.documentos if cumple(d)]

    def insert_one(self, documento: dict) -> None:
        self.documentos.append(dict(documento))


def correccion(i: int, temporada="OTONO", calidez=15.0, hace_horas=1, usuario=None) -> dict:
    # a = 10, b = 10 + calidez: piel_calidez = b - a = calidez.
    return {
        "_id": f"c{temporada}{i}",
        "usuario_id": usuario or f"sub-{i}",
        "piel": {"l": 60.0, "a": 10.0, "b": 10.0 + calidez},
        "temporada_confirmada": temporada,
        "creada_en": AHORA - timedelta(hours=hace_horas, minutes=i),
    }


def otonos(n: int, **kwargs) -> list[dict]:
    return [correccion(i, "OTONO", **kwargs) for i in range(n)]


def base_con(correcciones, recalibraciones=()) -> dict:
    base = {
        "centroides_colorimetria": falsos.ColeccionFalsa(),
        "correcciones_colorimetria": ColeccionSimple(*correcciones),
        "recalibraciones": ColeccionSimple(*recalibraciones),
    }
    repositorio = RepositorioCentroides(base["centroides_colorimetria"])
    repositorio.activar(repositorio.publicar(falsos.artefacto("prueba-v1")))
    return base


def vigente(base) -> dict:
    repositorio = RepositorioCentroides(base["centroides_colorimetria"])
    return repositorio.cargar(repositorio.version_vigente())


def fila(calidez: float, contraste: float, estacion: str) -> dict:
    return {"variables": {"piel_calidez": calidez, "contraste": contraste}, "estacion": estacion}


# Cuatro muestras bien clasificadas antes y despues de mover CALIDO a z = 1.5.
CONJUNTO_ESTABLE = [
    fila(10.0, 40.0, "OTONO"),
    fila(-10.0, 40.0, "INVIERNO"),
    fila(10.0, 20.0, "PRIMAVERA"),
    fila(-10.0, 20.0, "VERANO"),
]


@pytest.mark.parametrize(
    ("temporada", "estacion"),
    [
        ("OTONO", "OTONO"),
        ("otono_suave", "OTONO"),
        ("Otoño", "OTONO"),
        ("invierno", "INVIERNO"),
        ("x", None),
        (None, None),
    ],
)
def test_entiende_la_temporada_que_guarde_el_core(temporada, estacion):
    assert estacion_de(temporada) == estacion


def test_las_variables_de_piel_salen_del_lab():
    v = variables_de_piel({"l": 60.0, "a": 10.0, "b": 25.0})

    assert v["piel_calidez"] == 15.0
    assert v["piel_b_L"] == pytest.approx(25 / 60)
    assert "contraste" not in v and "cabello_L" not in v


def test_con_cabello_e_iris_salen_tambien_sus_variables_y_el_contraste():
    v = variables_medidas(
        {
            "piel": {"l": 60.0, "a": 10.0, "b": 25.0},
            "cabello": {"l": 10.0, "a": 2.0, "b": 3.0},
            "iris": {"l": 30.0, "a": 1.0, "b": 8.0},
        }
    )

    assert v["contraste"] == 50.0
    assert v["dL_piel_cabello"] == 50.0
    assert v["dL_piel_ojos"] == 30.0
    assert v["cabello_L"] == 10.0 and v["ojos_b"] == 8.0
    # S y V no salen del Lab: no se mueven nunca.
    assert not any(k.endswith(("_S", "_V")) for k in v)


def test_sin_cabello_el_contraste_cae_a_piel_ojos():
    v = variables_medidas(
        {"piel": {"l": 60.0, "a": 10.0, "b": 25.0}, "iris": {"l": 35.0, "a": 1.0, "b": 8.0}}
    )

    assert v["contraste"] == 25.0
    assert "cabello_L" not in v and "dL_piel_cabello" not in v


def test_sin_piel_no_hay_variables():
    assert variables_medidas({"cabello": {"l": 10.0, "a": 2.0, "b": 3.0}}) == {}


def test_con_cabello_tambien_se_mueve_el_contraste():
    # Piel L 60 y cabello L 10: contraste 50, z = 2. (25 * 1 + 20 * 2) / 45 = 1.44.
    correcciones = [{**c, "cabello": {"l": 10.0, "a": 2.0, "b": 3.0}} for c in otonos(20)]
    base = base_con(correcciones)

    recalibrar_en(base, CONJUNTO_ESTABLE, tope=10.0, ahora=AHORA)

    alto = vigente(base)["capas"]["contraste"]["centroides"]["ALTO"][0]
    assert alto == pytest.approx((25 * 1 + 20 * 2) / 45)


def test_sin_20_correcciones_por_estacion_no_hace_nada():
    base = base_con(otonos(MIN_CORRECCIONES_POR_ESTACION - 1))

    resultado = recalibrar_en(base, CONJUNTO_ESTABLE, ahora=AHORA)

    assert resultado.umbral_alcanzado is False
    assert base["recalibraciones"].documentos == []
    assert vigente(base)["version"] == "prueba-v1"


def test_mezcla_con_tope_y_solo_mueve_lo_medido():
    # 20 correcciones en z = 3: (25 * 1 + 20 * 3) / 45 = 1.89, que el tope deja en 1.5.
    correcciones = otonos(20)
    base = base_con(correcciones)

    resultado = recalibrar_en(base, CONJUNTO_ESTABLE, ahora=AHORA)

    nuevo = vigente(base)
    assert nuevo["version"] == "prueba-v1+r202610300300"
    assert nuevo["capas"]["subtono"]["centroides"] == {"CALIDO": [1.5], "FRIO": [-1.0]}
    # La correccion no trae cabello: el contraste no se mueve.
    assert nuevo["capas"]["contraste"]["centroides"] == {"ALTO": [1.0], "BAJO": [-1.0]}
    registro = base["recalibraciones"].documentos[0]
    assert registro["estado"] == "publicada"
    assert registro["version_base"] == "prueba-v1"
    assert registro["correcciones_hasta"] == max(c["creada_en"] for c in correcciones)
    assert resultado.umbral_alcanzado is True
    assert resultado.usuarios_afectados == 20


def test_sin_tope_la_mezcla_es_la_de_la_formula():
    base = base_con(otonos(20))

    recalibrar_en(base, CONJUNTO_ESTABLE, tope=10.0, ahora=AHORA)

    calido = vigente(base)["capas"]["subtono"]["centroides"]["CALIDO"][0]
    assert calido == pytest.approx((25 * 1 + 20 * 3) / 45)


def test_sin_conjunto_de_evaluacion_se_descarta_y_no_consume():
    base = base_con(otonos(20))

    recalibrar_en(base, None, ahora=AHORA)

    assert vigente(base)["version"] == "prueba-v1"
    registro = base["recalibraciones"].documentos[0]
    assert registro["estado"] == "descartada"
    assert "correcciones_hasta" not in registro


def test_si_empeora_mas_de_un_punto_se_descarta():
    # z = 0.05 es CALIDO con el centroide en 1, pero FRIO con el centroide en 1.5.
    conjunto = [fila(0.25, 40.0, "OTONO")]
    base = base_con(otonos(20))

    recalibrar_en(base, conjunto, ahora=AHORA)

    assert vigente(base)["version"] == "prueba-v1"
    registro = base["recalibraciones"].documentos[0]
    assert registro["estado"] == "descartada"
    assert "subtono" in registro["motivo"]
    assert registro["metricas"]["antes"]["subtono"] == 1.0


def test_solo_cuentan_las_posteriores_a_la_ultima_marca():
    viejas = otonos(20, hace_horas=48)
    desvinculada = {
        "_id": "d",
        "piel": {"l": 60, "a": 10, "b": 25},
        "temporada_confirmada": "OTONO",
        "mes": "2026-09",
    }
    marca = {"estado": "publicada", "correcciones_hasta": AHORA - timedelta(hours=24)}
    base = base_con([*viejas, desvinculada], [marca])

    resultado = recalibrar_en(base, CONJUNTO_ESTABLE, ahora=AHORA)

    assert resultado.umbral_alcanzado is False


def test_el_sufijo_de_version_no_se_acumula():
    assert version_recalibrada("v1+r202601010000", AHORA) == "v1+r202610300300"


def test_el_conjunto_ignora_filas_sin_estacion_valida(tmp_path):
    ruta = tmp_path / "conjunto.json"
    ruta.write_text(json.dumps([fila(1, 1, "OTONO"), fila(1, 1, "X"), {"estacion": "OTONO"}]))

    assert len(leer_conjunto(ruta)) == 1
