"""Rutas del entrenamiento del clasificador de prendas, FUERA del repositorio.

Por defecto `~/.wearhack/prendas.json`, o el que diga `WEARHACK_PRENDAS_CONFIG`:

    {"datos": "<fuentes descargadas>", "salida": "<dataset construido, pesos y metricas>"}

Solo libreria estandar: lo importan los tests y el paso de exportacion en WSL.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path

CLAVES = ("datos", "salida")


class ErrorDeConfiguracion(Exception):
    pass


@dataclass(frozen=True)
class Rutas:
    datos: Path
    salida: Path

    @property
    def fashionpedia(self) -> Path:
        return self.datos / "fashionpedia"

    @property
    def grigorev(self) -> Path:
        return self.datos / "clothing-dataset"

    @property
    def dataset(self) -> Path:
        """Recortes ya construidos y su manifiesto."""
        return self.salida / "dataset"


def esta_en_un_repositorio(ruta: Path) -> Path | None:
    actual = ruta.resolve()
    while True:
        if (actual / ".git").exists():
            return actual
        if actual.parent == actual:
            return None
        actual = actual.parent


def ruta_por_defecto() -> Path:
    env = os.environ.get("WEARHACK_PRENDAS_CONFIG")
    return Path(env) if env else Path.home() / ".wearhack" / "prendas.json"


def cargar(ruta_config: Path | None = None) -> Rutas:
    ruta_config = ruta_config or ruta_por_defecto()
    if not ruta_config.is_file():
        raise ErrorDeConfiguracion(
            f"No existe {ruta_config}. Crealo fuera del repositorio con las claves {CLAVES}."
        )
    repo = esta_en_un_repositorio(ruta_config)
    if repo:
        raise ErrorDeConfiguracion(f"{ruta_config} esta dentro del repositorio {repo}.")
    datos = json.loads(ruta_config.read_text(encoding="utf-8"))
    if not isinstance(datos, dict) or set(datos) != set(CLAVES):
        raise ErrorDeConfiguracion(f"{ruta_config} debe tener exactamente las claves {CLAVES}.")
    rutas = {}
    for clave in CLAVES:
        ruta = Path(datos[clave])
        ruta.mkdir(parents=True, exist_ok=True)
        repo = esta_en_un_repositorio(ruta)
        if repo:
            raise ErrorDeConfiguracion(
                f"{clave}: {ruta} esta dentro del repositorio {repo}. "
                "Ni imagenes ni pesos van en el repositorio."
            )
        rutas[clave] = ruta.resolve()
    return Rutas(**rutas)
