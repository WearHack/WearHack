"""Arranque comun de los jobs batch.

Un job es un proceso suelto: nadie configuro los logs ni las trazas por el.

Cada corrida termina con una linea de log estructurada (job, umbral_alcanzado,
usuarios_afectados, timestamp), que es lo que se mira con `docker compose logs`
en el host del lab para saber si un job hizo algo (protocolos seccion 11).
"""

import logging
import sys
import time
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime

from opentelemetry import trace

from app.config import ajustes
from app.logging_config import configurar_logs
from app.telemetry import configurar_trazas

log = logging.getLogger(__name__)


@dataclass(frozen=True)
class ResultadoJob:
    """Lo que un job cuenta de su corrida.

    `umbral_alcanzado` dice si algun usuario o estacion paso el umbral del job
    (por ejemplo, 10 selecciones nuevas): si es False, el job corrio y no cambio
    nada, que es normal y no un fallo.
    """

    umbral_alcanzado: bool
    usuarios_afectados: int = 0


def registrar_corrida(
    nombre: str,
    estado: str,
    resultado: ResultadoJob | None,
    duracion: float,
) -> None:
    """La linea de log de la corrida. Sin datos personales: solo conteos."""
    log.info(
        "Job %s: %s",
        nombre,
        estado,
        extra={
            "job": nombre,
            "estado": estado,
            "umbral_alcanzado": resultado.umbral_alcanzado if resultado else None,
            "usuarios_afectados": resultado.usuarios_afectados if resultado else None,
            "duracion_s": round(duracion, 3),
            "timestamp": datetime.now(UTC).isoformat(timespec="seconds").replace("+00:00", "Z"),
        },
    )


def ejecutar(nombre: str, tarea: Callable[[], ResultadoJob | None]) -> int:
    """Corre un job con logs, trazas y codigo de salida.

    Devuelve 0 si fue bien y 1 si fallo. Un job que no tiene nada que contar
    (una tarea de mantenimiento) puede devolver None.
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
            resultado = tarea()
        except Exception:
            log.exception("Job %s: fallo", nombre)
            registrar_corrida(nombre, "fallo", None, time.monotonic() - comienzo)
            return 1

    registrar_corrida(nombre, "termina", resultado, time.monotonic() - comienzo)
    return 0


def salir(nombre: str, tarea: Callable[[], ResultadoJob | None]) -> None:
    sys.exit(ejecutar(nombre, tarea))
