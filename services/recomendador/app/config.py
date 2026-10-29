"""Configuracion del servicio, leida del entorno.

Un solo sitio donde mirar cuando algo no toma el valor que esperabas.
"""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Ajustes(BaseSettings):
    model_config = SettingsConfigDict(env_file=None, extra="ignore")

    servicio: str = "recomendador"
    version: str = "0.1.0"
    entorno: str = "local"
    log_level: str = "INFO"

    # Pesos y reglas del motor, en Mongo (app/pesos.py).
    mongo_uri: str = "mongodb://localhost:27017/wearhack"
    # Cada cuanto se relee el documento `recomendacion` de `configuracion`, en segundos.
    intervalo_recarga_configuracion: float = 60.0

    # Observabilidad
    otel_exporter_otlp_endpoint: str = "http://otel-collector:4317"
    otel_sdk_disabled: bool = False


@lru_cache
def ajustes() -> Ajustes:
    """Cacheado: los ajustes no cambian en caliente y esto se llama por peticion."""
    return Ajustes()
