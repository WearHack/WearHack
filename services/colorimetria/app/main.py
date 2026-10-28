"""Servicio de colorimetria de WearHack.

Clasifica la estacion de color a partir del recorte facial que reenvia el Core
(`POST /v1/colorimetria/analizar`), con los centroides vigentes de Mongo.
"""

import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.concurrency import run_in_threadpool
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

from app.analisis import Analizador, ServicioColorimetria
from app.api.v1 import colorimetria
from app.centroides import CentroidesVigentes, RepositorioCentroides, abrir_coleccion
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
    mongo, servicio = crear_servicio(config)
    app.state.colorimetria = servicio
    # Los centroides se cargan ya, no con la primera peticion. Si Mongo no
    # responde, el servicio arranca igual y los busca en la siguiente.
    await run_in_threadpool(servicio.centroides.actual)
    log.info("Servicio %s %s listo (%s)", config.servicio, config.version, config.entorno)
    yield
    log.info("Servicio %s parando", config.servicio)
    servicio.analizador.cerrar()
    mongo.close()


def crear_servicio(config) -> tuple:
    """El cliente de Mongo y el servicio. Los modelos de MediaPipe se cargan con
    la primera peticion, cuando ya se sabe que version de centroides los pide.
    """
    mongo, coleccion = abrir_coleccion(config.mongo_uri)
    centroides = CentroidesVigentes(
        RepositorioCentroides(coleccion), config.intervalo_recarga_centroides
    )
    return mongo, ServicioColorimetria(centroides, Analizador(Path(config.ruta_modelos)))


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
