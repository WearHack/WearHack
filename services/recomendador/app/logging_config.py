"""Logs estructurados en JSON hacia stdout.

En ECS el driver awslogs los recoge y los manda a CloudWatch Logs tal cual.
Cada linea lleva trace_id y span_id, para poder cruzar un log con su traza.
"""

import logging
import sys
from datetime import datetime, timezone

from opentelemetry import trace
from pythonjsonlogger.json import JsonFormatter


class ContextoDeTraza(logging.Filter):
    """Anade trace_id y span_id a cada registro, si hay un span activo."""

    def filter(self, record: logging.LogRecord) -> bool:
        contexto = trace.get_current_span().get_span_context()
        if contexto.is_valid:
            record.trace_id = format(contexto.trace_id, "032x")
            record.span_id = format(contexto.span_id, "016x")
        return True


class FormatoWearHack(JsonFormatter):
    """JSON con el mismo timestamp que emiten los servicios Java.

    El formato por defecto de logging es '2026-09-21 22:42:05,324', que no es
    ISO 8601: mezcla espacio en vez de T, coma en vez de punto y no dice la
    zona. Dos formatos distintos conviviendo obligan a escribir dos consultas
    en CloudWatch para lo mismo.
    """

    def add_fields(self, log_record, record, message_dict):
        super().add_fields(log_record, record, message_dict)
        log_record["momento"] = (
            datetime.fromtimestamp(record.created, timezone.utc)
            .isoformat(timespec="microseconds")
            .replace("+00:00", "Z")
        )
        # uvicorn adjunta una copia del mensaje con codigos de escape ANSI para
        # pintarlo en una terminal. Dentro de un JSON que va a CloudWatch solo
        # son bytes basura repetidos en cada linea.
        log_record.pop("color_message", None)


def configurar_logs(servicio: str, nivel: str = "INFO") -> None:
    formato = FormatoWearHack(
        "{levelname}{name}{message}",
        style="{",
        rename_fields={
            "levelname": "nivel",
            "name": "origen",
            "message": "mensaje",
        },
        static_fields={"servicio": servicio},
        timestamp=False,
    )

    manejador = logging.StreamHandler(sys.stdout)
    manejador.setFormatter(formato)
    manejador.addFilter(ContextoDeTraza())

    raiz = logging.getLogger()
    raiz.handlers.clear()
    raiz.addHandler(manejador)
    raiz.setLevel(nivel.upper())

    # uvicorn trae sus propios manejadores con formato propio. Sin esto, la
    # mitad de las lineas saldria en JSON y la otra mitad en texto plano.
    for nombre in ("uvicorn", "uvicorn.error"):
        registro = logging.getLogger(nombre)
        registro.handlers.clear()
        registro.propagate = True

    # uvicorn.access se trata aparte: cuando se arranca con --no-access-log,
    # uvicorn lo apaga poniendo propagate a False. Forzarlo a True aqui lo
    # reviviria, y volveriamos a pagar una linea de log por cada health check,
    # cada diez segundos, en todos los servicios. Solo le cambiamos el formato
    # a quien ya iba a escribir.
    acceso = logging.getLogger("uvicorn.access")
    acceso.handlers.clear()
