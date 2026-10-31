"""Rutas del analisis, FUERA del repositorio.

Por defecto `~/.wearhack/normalizacion.json`, o el que diga
`WEARHACK_NORMALIZACION_CONFIG`:

    {
      "lotes": "<carpeta de la boveda con los lotes importados>",
      "modelos_mediapipe": "<carpeta con los dos modelos>",
      "artefacto": "<centroides-4-estaciones-v1.json>",
      "salida": "<carpeta de resultados, en la boveda>",
      "tarjetas": "<tarjetas.json con las cajas marcadas> (opcional)",
      "grupos_tono": "<grupos_tono.json: seudonimo -> tono Monk 1-10> (opcional)",
      "mst_e": {"imagenes": "<carpeta>", "etiquetas": "<csv archivo,monk>"} (opcional)
    }

Fotos de rostros, tonos de piel y resultados son datos de calibracion: ninguna
ruta puede caer dentro de un repositorio git.
"""

import json
import os
from dataclasses import dataclass
from pathlib import Path

OBLIGATORIAS = ("lotes", "modelos_mediapipe", "artefacto", "salida")
OPCIONALES = ("tarjetas", "grupos_tono", "mst_e")


class ErrorDeConfiguracion(Exception):
    pass


@dataclass(frozen=True)
class MstE:
    imagenes: Path
    etiquetas: Path


@dataclass(frozen=True)
class Rutas:
    lotes: Path
    modelos_mediapipe: Path
    artefacto: Path
    salida: Path
    tarjetas: Path | None = None
    grupos_tono: Path | None = None
    mst_e: MstE | None = None

    @property
    def mediciones(self) -> Path:
        return self.salida / "mediciones.csv"


def esta_en_un_repositorio(ruta: Path) -> Path | None:
    actual = ruta.resolve()
    while True:
        if (actual / ".git").exists():
            return actual
        if actual.parent == actual:
            return None
        actual = actual.parent


def ruta_por_defecto() -> Path:
    env = os.environ.get("WEARHACK_NORMALIZACION_CONFIG")
    return Path(env) if env else Path.home() / ".wearhack" / "normalizacion.json"


def _fuera_del_repo(clave: str, ruta: Path) -> Path:
    repo = esta_en_un_repositorio(ruta)
    if repo:
        raise ErrorDeConfiguracion(
            f"{clave}: {ruta} esta dentro del repositorio {repo}. "
            "Ni fotos ni tonos de piel ni resultados van en un repositorio."
        )
    return ruta.resolve()


def cargar(ruta_config: Path | None = None) -> Rutas:
    ruta_config = ruta_config or ruta_por_defecto()
    if not ruta_config.is_file():
        raise ErrorDeConfiguracion(
            f"No existe {ruta_config}. Crealo fuera del repositorio con las claves {OBLIGATORIAS}."
        )
    if esta_en_un_repositorio(ruta_config):
        raise ErrorDeConfiguracion(f"{ruta_config} esta dentro de un repositorio.")
    datos = json.loads(ruta_config.read_text(encoding="utf-8"))
    if not isinstance(datos, dict):
        raise ErrorDeConfiguracion(f"{ruta_config} debe ser un objeto JSON.")
    faltan = [c for c in OBLIGATORIAS if c not in datos]
    sobran = [c for c in datos if c not in OBLIGATORIAS + OPCIONALES]
    if faltan or sobran:
        raise ErrorDeConfiguracion(f"{ruta_config}: faltan {faltan}, sobran {sobran}.")

    rutas = {c: _fuera_del_repo(c, Path(datos[c])) for c in OBLIGATORIAS}
    rutas["salida"].mkdir(parents=True, exist_ok=True)
    for c in ("tarjetas", "grupos_tono"):
        if datos.get(c):
            rutas[c] = _fuera_del_repo(c, Path(datos[c]))
    if datos.get("mst_e"):
        m = datos["mst_e"]
        rutas["mst_e"] = MstE(
            imagenes=_fuera_del_repo("mst_e.imagenes", Path(m["imagenes"])),
            etiquetas=_fuera_del_repo("mst_e.etiquetas", Path(m["etiquetas"])),
        )
    return Rutas(**rutas)


def cargar_grupos_tono(ruta: Path | None) -> dict[str, int]:
    """Seudonimo -> tono Monk (1-10). Vacio si no hay archivo."""
    if ruta is None or not ruta.is_file():
        return {}
    datos = json.loads(ruta.read_text(encoding="utf-8"))
    grupos = {}
    for seudonimo, tono in datos.items():
        if not isinstance(tono, int) or not 1 <= tono <= 10:
            raise ErrorDeConfiguracion(f"Tono Monk invalido para {seudonimo}: {tono!r}")
        grupos[seudonimo] = tono
    return grupos


def grupo_de_tono(tono: int) -> str:
    """Los tres grupos del protocolo (M5)."""
    return "1-3" if tono <= 3 else "4-7" if tono <= 7 else "8-10"
