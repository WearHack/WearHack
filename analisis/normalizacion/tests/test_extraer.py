"""Medir una toma con un segmentador falso: sin MediaPipe ni rostros reales."""

from dataclasses import asdict

import numpy as np

from normalizacion.extraer import medir_toma
from normalizacion.metricas import delta_e_00
from normalizacion.tecnicas import angulo

from app.centroides import Artefacto
from app.extraccion.color import lineal_a_srgb
from app.extraccion.segmentacion import ParametrosSegmentacion, Regiones, SinRostro

LUZ_CALIDA = np.array([1.0, 0.8, 0.55])
# Misma intensidad media que la calida: von Kries corrige el color de la luz,
# no su intensidad (eso lo hace la exposicion de la camara).
NEUTRA = np.full(3, LUZ_CALIDA.mean())
PIEL, CABELLO, OJOS, BLANCO_OJO = (0.40, 0.25, 0.17), (0.04, 0.03, 0.02), (0.10, 0.06, 0.04), (0.6, 0.6, 0.6)


def artefacto() -> Artefacto:
    segmentacion = asdict(ParametrosSegmentacion())
    segmentacion["modelos"] = {"face_landmarker.task": "x"}
    return Artefacto.desde_dict(
        {
            "version": "prueba",
            "estandarizacion": {
                "media": {"piel_calidez": 0.0, "contraste": 30.0},
                "desviacion": {"piel_calidez": 5.0, "contraste": 10.0},
            },
            "capas": {
                "subtono": {"variables": ["piel_calidez"], "centroides": {"CALIDO": [1.0], "FRIO": [-1.0]}},
                "contraste": {"variables": ["contraste"], "centroides": {"ALTO": [1.0], "BAJO": [-1.0]}},
            },
            "muestreo": {
                "piel_y_cabello": "mediana_p0_100",
                "ojos": "mediana_p0_100",
                "pixeles_minimos": {"piel": 50, "cabello": 50, "ojos": 4},
            },
            "segmentacion": segmentacion,
        }
    )


class Segmentador:
    """Regiones fijas de una cara sintetica iluminada por `luz`."""

    def __init__(self, luz, sin_rostro=False):
        self.luz = np.asarray(luz)
        self.sin_rostro = sin_rostro

    def regiones(self, _rgb):
        if self.sin_rostro:
            raise SinRostro()
        forma = (60, 40)
        mascaras = {n: np.zeros(forma, bool) for n in ("piel", "cabello", "ojos", "esclerotica")}
        mascaras["cabello"][:15] = True
        mascaras["piel"][15:45] = True
        mascaras["ojos"][45:50, 5:15] = True
        mascaras["esclerotica"][50:56, 5:35] = True
        lineal = np.full((*forma, 3), 0.2)
        for nombre, refl in (
            ("cabello", CABELLO),
            ("piel", PIEL),
            ("ojos", OJOS),
            ("esclerotica", BLANCO_OJO),
        ):
            lineal[mascaras[nombre]] = np.asarray(refl) * self.luz
        rgb = np.round(lineal_a_srgb(lineal)).astype(np.uint8)
        return Regiones(rgb=rgb, ancho_rostro=30.0, **mascaras)


def _por_tecnica(filas):
    return {f["tecnica"]: f for f in filas}


def _lab(fila):
    return np.array([fila["piel_L"], fila["piel_a"], fila["piel_b"]])


def test_mide_cada_tecnica_y_t1_quita_la_luz_calida():
    recorte = np.zeros((10, 10, 3), np.uint8)
    calida = _por_tecnica(medir_toma(recorte, Segmentador(LUZ_CALIDA), artefacto(), None)[0])
    neutra = _por_tecnica(medir_toma(recorte, Segmentador(NEUTRA), artefacto(), None)[0])

    assert set(calida) == {"T0", "T1", "T2", "REF"}
    assert calida["REF"]["motivo"] == "sin_tarjeta"
    assert calida["T1"]["motivo"] == ""
    # Sin corregir, la luz calida mueve la piel; T1 la devuelve casi a donde estaba.
    error_t0 = float(delta_e_00(_lab(calida["T0"]), _lab(neutra["T0"])))
    error_t1 = float(delta_e_00(_lab(calida["T1"]), _lab(neutra["T0"])))
    assert error_t0 > 5
    assert error_t1 < 1.5
    assert angulo([calida["T1"][f"luz_{c}"] for c in "rgb"], LUZ_CALIDA) < 1


def test_con_tarjeta_ref_usa_su_luz():
    filas, _ = medir_toma(
        np.zeros((10, 10, 3), np.uint8), Segmentador(LUZ_CALIDA), artefacto(), LUZ_CALIDA * 0.2
    )
    ref = _por_tecnica(filas)["REF"]
    assert ref["motivo"] == ""
    assert angulo([ref[f"luz_{c}"] for c in "rgb"], LUZ_CALIDA) < 1e-6
    assert ref["subtono"] in ("CALIDO", "FRIO")


def test_sin_rostro_todas_las_tecnicas_lo_dicen():
    filas, controles = medir_toma(
        np.zeros((10, 10, 3), np.uint8), Segmentador(NEUTRA, True), artefacto(), None
    )
    assert {f["motivo"] for f in filas} == {"sin_rostro"}
    assert "quemados_pct" in controles
