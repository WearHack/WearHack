"""Del PNG a la estacion, con un segmentador falso: sin MediaPipe ni rostros."""

import functools
import json

import pytest

from app.analisis import (
    Analizador,
    RecorteInvalido,
    ServicioColorimetria,
    ServicioNoDisponible,
    decodificar_png,
)
from app.centroides import Artefacto, ArtefactoInvalido, CentroidesVigentes, RepositorioCentroides
from app.clasificador import ESTACIONES
from app.extraccion.muestreo import Variante
from tests import falsos


@pytest.fixture
def modelos(tmp_path):
    falsos.escribir_modelos(tmp_path)
    falsos.SegmentadorFalso.creados = 0
    return tmp_path


def servicio(modelos, datos=None, **segmentador) -> ServicioColorimetria:
    coleccion = falsos.ColeccionFalsa()
    repositorio = RepositorioCentroides(coleccion)
    if datos is not False:
        repositorio.publicar(datos or falsos.artefacto())
        repositorio.activar((datos or falsos.artefacto())["version"])
    fabrica = functools.partial(falsos.SegmentadorFalso, **segmentador)
    return ServicioColorimetria(CentroidesVigentes(repositorio, 60), Analizador(modelos, fabrica))


def test_la_variante_se_reconstruye_desde_su_nombre():
    for v in (Variante("mediana", 20, 80), Variante("media"), Variante("mediana", 2.5, 97.5)):
        assert Variante.desde_nombre(v.nombre) == v
    with pytest.raises(ValueError):
        Variante.desde_nombre("moda_p0_100")


def test_el_artefacto_sin_hashes_de_modelos_se_rechaza():
    datos = falsos.artefacto()
    datos["segmentacion"]["modelos"] = {}
    with pytest.raises(ArtefactoInvalido):
        Artefacto.desde_dict(datos)
    with pytest.raises(ArtefactoInvalido):
        Artefacto.desde_dict({"version": "x"})


def test_el_artefacto_real_tiene_la_forma_esperada():
    """El artefacto de `calibracion/` usa piel_y_cabello y ojos; los dos se respetan."""
    a = Artefacto.desde_dict(falsos.artefacto())
    assert a.variantes["piel"] == a.variantes["cabello"] == Variante("mediana")
    assert a.variantes["ojos"] == Variante("mediana", 20, 80)
    assert a.minimos == {"piel": 50, "cabello": 50, "ojos": 4}


def test_responde_con_la_forma_que_valida_el_core(modelos):
    r = servicio(modelos).analizar_png(falsos.png())

    # Lo que exige ClienteColorimetriaHttp del Core.
    assert r["temporada"] in ESTACIONES
    assert 0 <= r["confianza"] <= 1
    assert isinstance(r["ejes"], list) and r["ejes"]
    assert set(r["piel"]) == {"l", "a", "b"}
    # Piel calida y cabello mucho mas oscuro: calido y contraste alto.
    assert r["temporada"] == "OTONO"
    assert r["confianza"] == max(r["probabilidades"]["estaciones"].values())
    assert sum(r["probabilidades"]["estaciones"].values()) == pytest.approx(1)
    assert r["segunda_opcion"] != r["temporada"]
    assert r["version_centroides"] == "prueba-v1"
    assert r["iris"] is not None


def test_sin_cabello_no_se_imputa(modelos):
    r = servicio(modelos, sin_cabello=True).analizar_png(falsos.png())

    assert r["cabello"] is None
    # El contraste cae a piel-ojos (A.3) y sigue habiendo clasificacion.
    assert r["temporada"] in ESTACIONES


def test_sin_rostro_o_sin_piel_el_recorte_no_sirve(modelos):
    with pytest.raises(RecorteInvalido, match="rostro"):
        servicio(modelos, sin_rostro=True).analizar_png(falsos.png())
    with pytest.raises(RecorteInvalido, match="piel"):
        servicio(modelos, sin_piel=True).analizar_png(falsos.png())


def test_sin_centroides_vigentes_el_servicio_no_esta_disponible(modelos):
    with pytest.raises(ServicioNoDisponible, match="centroides"):
        servicio(modelos, datos=False).analizar_png(falsos.png())


def test_con_otros_modelos_no_responde(modelos):
    """Otro modelo segmentaria distinto y los centroides no valdrian."""
    (modelos / "face_landmarker.task").write_bytes(b"otra version")
    with pytest.raises(ServicioNoDisponible, match="face_landmarker"):
        servicio(modelos).analizar_png(falsos.png())


def test_el_segmentador_se_carga_una_vez(modelos):
    s = servicio(modelos)
    for _ in range(3):
        s.analizar_png(falsos.png())
    assert falsos.SegmentadorFalso.creados == 1


def test_solo_acepta_png_legible():
    with pytest.raises(RecorteInvalido, match="PNG"):
        decodificar_png(falsos.png(formato="JPEG"))
    with pytest.raises(RecorteInvalido):
        decodificar_png(b"\x89PNG\r\n\x1a\n esto no es un png")


def test_un_png_con_perfil_icc_se_convierte_a_srgb():
    from PIL import ImageCms

    srgb = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
    rgb = decodificar_png(falsos.png(ancho=5, alto=3, icc=srgb))

    assert rgb.shape == (3, 5, 3)
    # sRGB a sRGB no debe mover el color mas que el redondeo.
    assert abs(int(rgb[0, 0, 0]) - 120) <= 2


def test_el_artefacto_se_guarda_tal_cual():
    coleccion = falsos.ColeccionFalsa()
    RepositorioCentroides(coleccion).publicar(falsos.artefacto())
    guardado = coleccion.documentos["prueba-v1"]["artefacto"]
    assert json.loads(guardado) == falsos.artefacto()
