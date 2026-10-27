"""Rutas de datos, modelos y salidas, leidas de un archivo FUERA del repositorio.

Por defecto `~/.wearhack/entrenamiento.json`, o el que diga la variable
`WEARHACK_ENTRENAMIENTO_CONFIG`:

    {
      "deep_armocromia": "<carpeta con train/ y test/>",
      "modelos_mediapipe": "<carpeta con face_landmarker.task y selfie_multiclass_256x256.tflite>",
      "salida": "<carpeta donde se escriben variables, centroides e informes>"
    }

Son rostros y datos derivados de ellos: ninguna de las tres rutas puede estar
dentro de un repositorio git, y el archivo tampoco.
"""

import json
import os
from dataclasses import dataclass
from pathlib import Path

CLAVES = ("deep_armocromia", "modelos_mediapipe", "salida")
LANDMARKER = "face_landmarker.task"
SEGMENTADOR = "selfie_multiclass_256x256.tflite"


class ErrorDeConfiguracion(Exception):
    pass


@dataclass(frozen=True)
class Rutas:
    deep_armocromia: Path
    modelos_mediapipe: Path
    salida: Path

    @property
    def landmarker(self) -> Path:
        return self.modelos_mediapipe / LANDMARKER

    @property
    def segmentador(self) -> Path:
        return self.modelos_mediapipe / SEGMENTADOR


def esta_en_un_repositorio(ruta: Path) -> Path | None:
    """El repositorio que contiene a `ruta` (la carpeta con .git), o None."""
    actual = ruta.resolve()
    while True:
        if (actual / ".git").exists():
            return actual
        if actual.parent == actual:
            return None
        actual = actual.parent


def ruta_por_defecto() -> Path:
    env = os.environ.get("WEARHACK_ENTRENAMIENTO_CONFIG")
    return Path(env) if env else Path.home() / ".wearhack" / "entrenamiento.json"


def cargar(ruta_config: Path | None = None) -> Rutas:
    ruta_config = ruta_config or ruta_por_defecto()
    if not ruta_config.is_file():
        raise ErrorDeConfiguracion(
            f"No existe {ruta_config}. Crealo fuera del repositorio con las claves {CLAVES}."
        )
    if repo := esta_en_un_repositorio(ruta_config):
        raise ErrorDeConfiguracion(f"{ruta_config} esta dentro del repositorio {repo}.")
    try:
        datos = json.loads(ruta_config.read_text(encoding="utf-8"))
    except (ValueError, OSError) as e:
        raise ErrorDeConfiguracion(f"No se pudo leer {ruta_config}: {e}") from e
    if not isinstance(datos, dict) or set(datos) != set(CLAVES):
        raise ErrorDeConfiguracion(f"{ruta_config} debe tener exactamente las claves {CLAVES}.")

    rutas = {}
    for clave in CLAVES:
        ruta = Path(datos[clave])
        if clave == "salida":
            ruta.mkdir(parents=True, exist_ok=True)
        if not ruta.is_dir():
            raise ErrorDeConfiguracion(f"{clave}: {ruta} no existe o no es una carpeta.")
        if repo := esta_en_un_repositorio(ruta):
            raise ErrorDeConfiguracion(
                f"{clave}: {ruta} esta dentro del repositorio {repo}. "
                "Ni los rostros ni lo que se deriva de ellos van en un repositorio."
            )
        rutas[clave] = ruta.resolve()
    resultado = Rutas(**rutas)
    for modelo in (resultado.landmarker, resultado.segmentador):
        if not modelo.is_file():
            raise ErrorDeConfiguracion(f"Falta el modelo {modelo}. Ver el README de calibracion.")
    return resultado
