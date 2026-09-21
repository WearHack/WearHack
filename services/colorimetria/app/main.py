"""Servicio de colorimetria de WearHack.

Esqueleto. Arranca, responde /health y emite trazas. Nada mas.
"""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

from app.api.v1 import colorimetria
from app.config import ajustes
from app.health import router as router_health
from app.logging_config import configurar_logs
from app.telemetry import configurar_trazas

log = logging.getLogger(__name__)


@asynccontextmanager
async def ciclo_de_vida(app: FastAPI):
    config = ajustes()
    configurar_logs(config.servicio, config.log_level)
    configurar_trazas(
        servicio=config.servicio,
        version=config.version,
        entorno=config.entorno,
        endpoint=config.otel_exporter_otlp_endpoint,
        desactivado=config.otel_sdk_disabled,
    )
    log.info("Servicio %s %s listo (%s)", config.servicio, config.version, config.entorno)
    yield
    log.info("Servicio %s parando", config.servicio)


def crear_app() -> FastAPI:
    config = ajustes()
    app = FastAPI(
        title="WearHack :: colorimetria",
        version=config.version,
        lifespan=ciclo_de_vida,
    )
    # El mismo health en dos rutas, cada una con su publico.
    # /health lo llama el healthcheck del contenedor y, en AWS, el target
    # group del ALB. El de /api/v1/<servicio> es el que sale por el
    # gateway, y existe para que los seis servicios respondan igual: sin
    # el, el gateway tendria que reescribir la ruta solo para los dos
    # servicios de Python.
    app.include_router(router_health)
    app.include_router(router_health, prefix=f"/api/v1/{config.servicio}")
    app.include_router(colorimetria.router)

    # /health queda fuera de las trazas: lo llama el healthcheck del contenedor
    # cada diez segundos y llenaria el collector de ruido sin aportar nada.
    FastAPIInstrumentor.instrument_app(app, excluded_urls="health")
    return app


app = crear_app()
