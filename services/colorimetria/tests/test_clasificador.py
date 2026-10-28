"""Clasificador jerarquico con centroides de juguete."""

import math

import numpy as np
import pytest

from app.clasificador import Capa, ClasificadorJerarquico, distancias


def _clasificador() -> ClasificadorJerarquico:
    return ClasificadorJerarquico(
        capas={
            "subtono": Capa(["calidez"], ["CALIDO", "FRIO"], np.array([[1.0], [-1.0]])),
            "contraste": Capa(
                ["contraste", "dL"], ["ALTO", "BAJO"], np.array([[1.0, 1.0], [-1.0, -1.0]])
            ),
        },
        media={"calidez": 0.0, "contraste": 0.0, "dL": 0.0},
        desviacion={"calidez": 1.0, "contraste": 1.0, "dL": 1.0},
        version="prueba",
    )


def test_calido_y_alto_es_otono_con_segunda_opcion_vecina():
    r = _clasificador().clasificar({"calidez": 0.8, "contraste": 0.9, "dL": 1.2})
    assert r.estacion == "OTONO"
    assert r.segunda_opcion in {"INVIERNO", "PRIMAVERA"}
    assert sum(r.probabilidades.values()) == pytest.approx(1)


def test_un_eje_que_falta_se_salta_sin_imputar():
    r = _clasificador().clasificar({"calidez": -0.5, "contraste": math.nan, "dL": -1})
    assert r.estacion == "VERANO"
    assert "contraste" not in r.ejes_usados


def test_sin_ningun_eje_en_una_capa_no_clasifica():
    assert _clasificador().clasificar({"calidez": 1.0}) is None


def test_distancia_proyectada():
    d = distancias(np.array([[3.0, math.nan]]), np.array([[0.0, 0.0]]))
    assert d[0, 0] == pytest.approx(3)


def test_ida_y_vuelta_por_json():
    original = _clasificador()
    copia = ClasificadorJerarquico.desde_dict(original.a_dict())
    entrada = {"calidez": 0.3, "contraste": -0.2, "dL": 0.1}
    assert copia.clasificar(entrada) == original.clasificar(entrada)
