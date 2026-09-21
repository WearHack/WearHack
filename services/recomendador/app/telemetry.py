"""Cableado de OpenTelemetry.

El equivalente al agente Java de los servicios de negocio, pero explicito. Se
llama una vez al arrancar el proceso, y tambien desde los jobs batch, que sin
esto emitirian trazas a ninguna parte.
"""

import logging

from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

log = logging.getLogger(__name__)


def configurar_trazas(servicio: str, version: str, entorno: str,
                      endpoint: str, desactivado: bool = False) -> None:
    if desactivado:
        log.warning("OpenTelemetry desactivado por configuracion: no se emiten trazas.")
        return

    recurso = Resource.create({
        "service.name": servicio,
        "service.version": version,
        "deployment.environment.name": entorno,
    })

    proveedor = TracerProvider(resource=recurso)
    # En lote y no una por una: exportar cada span en el momento anadiria una
    # llamada de red por peticion.
    proveedor.add_span_processor(
        BatchSpanProcessor(OTLPSpanExporter(endpoint=endpoint, insecure=True))
    )
    trace.set_tracer_provider(proveedor)
    log.info("Trazas de OpenTelemetry hacia %s", endpoint)
