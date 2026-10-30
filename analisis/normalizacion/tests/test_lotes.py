"""Leer las tomas de la boveda, con lotes sinteticos y la configuracion."""

import json
from pathlib import Path

import pytest

from normalizacion import configuracion, lotes
from normalizacion.configuracion import ErrorDeConfiguracion, grupo_de_tono

from normalizacion import RAIZ_REPO

EJEMPLO = json.loads(
    (RAIZ_REPO / "tools" / "captura" / "ejemplos" / "metadatos_ejemplo.json").read_text(encoding="utf-8")
)


def escribir_toma(carpeta: Path, seudonimo="P3", luz="LEDC", celular="D2", rep="R1", tarjeta=True):
    base = f"{seudonimo}_{luz}_{celular}_{rep}_{'G' if tarjeta else 'N'}"
    datos = json.loads(json.dumps(EJEMPLO))
    datos.update(seudonimo=seudonimo, luz=luz, repeticion=rep, tarjeta_gris=tarjeta)
    datos["celular"]["codigo"] = celular
    datos["archivos"]["foto"] = f"{base}_foto.jpg"
    datos["archivos"]["recorte"] = f"{base}_recorte.png"
    carpeta.mkdir(parents=True, exist_ok=True)
    (carpeta / f"{base}.json").write_text(json.dumps(datos), encoding="utf-8")
    (carpeta / f"{base}_foto.jpg").write_bytes(b"\xff\xd8 foto")
    (carpeta / f"{base}_recorte.png").write_bytes(b"\x89PNG recorte")
    return base


def test_lee_tomas_de_varios_lotes_y_deja_fuera_d3(tmp_path):
    escribir_toma(tmp_path / "lote_1", seudonimo="P1", celular="D1")
    escribir_toma(tmp_path / "lote_2", seudonimo="P2", celular="D2", rep="R2", tarjeta=False)
    escribir_toma(tmp_path / "lote_2", seudonimo="P2", celular="D3")
    (tmp_path / "lote_1" / "manifiesto.json").write_text("{}", encoding="utf-8")

    carga = lotes.cargar(tmp_path)
    assert [t.id for t in carga.tomas] == ["P1_LEDC_D1_R1_G", "P2_LEDC_D2_R2_N"]
    assert carga.excluidas_d3 == 1
    assert carga.problemas == []
    assert carga.tomas[0].luz_normal and carga.tomas[0].tarjeta
    assert carga.tomas[0].ancho_rostro == EJEMPLO["rostro"]["ancho_px"]

    con_d3 = lotes.cargar(tmp_path, incluir_d3=True)
    assert len(con_d3.tomas) == 3


def test_lo_invalido_o_repetido_se_reporta(tmp_path):
    base = escribir_toma(tmp_path / "a")
    escribir_toma(tmp_path / "b")  # la misma toma en otro lote
    roto = escribir_toma(tmp_path / "c", seudonimo="P4")
    datos = json.loads((tmp_path / "c" / f"{roto}.json").read_text(encoding="utf-8"))
    datos["luz"] = "SOL"
    (tmp_path / "c" / f"{roto}.json").write_text(json.dumps(datos), encoding="utf-8")
    sin_foto = escribir_toma(tmp_path / "d", seudonimo="P5")
    (tmp_path / "d" / f"{sin_foto}_foto.jpg").unlink()

    carga = lotes.cargar(tmp_path)
    assert [t.id for t in carga.tomas] == [base]
    assert len(carga.problemas) == 3


def _config(tmp_path, **datos) -> Path:
    ruta = tmp_path / "normalizacion.json"
    ruta.write_text(json.dumps(datos), encoding="utf-8")
    return ruta


def test_la_configuracion_rechaza_rutas_dentro_de_un_repo(tmp_path):
    repo = tmp_path / "repo"
    (repo / ".git").mkdir(parents=True)
    fuera = tmp_path / "fuera"
    ruta = _config(
        tmp_path, lotes=str(fuera), modelos_mediapipe=str(fuera), artefacto=str(fuera / "a.json"),
        salida=str(repo / "salida"),
    )  # fmt: skip
    with pytest.raises(ErrorDeConfiguracion, match="salida"):
        configuracion.cargar(ruta)


def test_la_configuracion_pide_las_claves_obligatorias(tmp_path):
    with pytest.raises(ErrorDeConfiguracion, match="faltan"):
        configuracion.cargar(_config(tmp_path, lotes=str(tmp_path)))


def test_grupos_de_tono(tmp_path):
    ruta = tmp_path / "grupos.json"
    ruta.write_text(json.dumps({"P1": 2, "P2": 7}), encoding="utf-8")
    assert configuracion.cargar_grupos_tono(ruta) == {"P1": 2, "P2": 7}
    assert configuracion.cargar_grupos_tono(None) == {}
    ruta.write_text(json.dumps({"P1": 11}), encoding="utf-8")
    with pytest.raises(ErrorDeConfiguracion):
        configuracion.cargar_grupos_tono(ruta)
    assert [grupo_de_tono(t) for t in (1, 3, 4, 7, 8, 10)] == ["1-3", "1-3", "4-7", "4-7", "8-10", "8-10"]
