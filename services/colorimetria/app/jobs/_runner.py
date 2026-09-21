"""Arranque comun de los jobs batch.

Un job es un proceso suelto: nadie configuro los logs ni las trazas por el.
"""

import logging
import sys
import time
from collections.abc import Callable

from opentelemetry import trace

from app.config import ajustes
from app.logging_config import configurar_logs
from app.telemetry import configurar_trazas

log = logging.getLogger(__name__)


def ejecutar(nombre: str, tarea: Callable[[], None]) -> int:
    """Corre un job con logs, trazas y codigo de salida.

    Devuelve 0 si fue bien y 1 si fallo, que es lo que ECS mira para saber si
    la tarea programada termino bien.
    """
    config = ajustes()
    configurar_logs(f"{config.servicio}.jobs", config.log_level)
    configurar_trazas(
        servicio=f"{config.servicio}-jobs",
        version=config.version,
        entorno=config.entorno,
        endpoint=config.otel_exporter_otlp_endpoint,
        desactivado=config.otel_sdk_disabled,
    )

    tracer = trace.get_tracer(__name__)
    comienzo = time.monotonic()

    with tracer.start_as_current_span(f"job.{nombre}"):
        log.info("Job %s: comienza", nombre)
        try:
            tarea()
        except Exception:
            log.exception("Job %s: fallo", nombre)
            return 1

    log.info("Job %s: termina en %.2fs", nombre, time.monotonic() - comienzo)
    return 0


def salir(nombre: str, tarea: Callable[[], None]) -> None:
    sys.exit(ejecutar(nombre, tarea))
