# ADR 0012: OpenTelemetry en todos los servicios desde el primer dia

- **Estado:** aceptado
- **Fecha:** 2026-09-22

## Contexto

Una peticion cruza el gateway y uno o varios servicios en dos lenguajes.
Depurar eso con logs sueltos por servicio no es viable.

## Decision

OpenTelemetry en los siete servicios, desde el esqueleto:

- **Java:** el agente `opentelemetry-javaagent`, sin tocar codigo.
- **Python:** el SDK configurado a mano mas `opentelemetry-instrumentation-fastapi`.

Logs estructurados en JSON a stdout, con `trace_id` y `span_id` en cada linea y
**el mismo formato de timestamp** en los dos lenguajes. En ECS el driver
`awslogs` los lleva a CloudWatch tal cual.

Un collector recibe todo por OTLP. En local exporta a consola; en AWS cambian
los exporters a X-Ray y CloudWatch, y el resto queda igual.

## Consecuencias

Un log se cruza con su traza sin trabajo extra, y una peticion se sigue de punta
a punta atravesando los dos lenguajes.

El agente Java cuesta alrededor de un segundo de arranque y unos 40 MB. Si el
arranque en frio molesta en Fargate, la alternativa es `micrometer-tracing` con
exportador OTLP: instrumenta menos pero arranca antes.

En Python el SDK se configura a mano en vez de usar el arranque automatico. Es
mas codigo, pero se lee y se depura mejor, que importa con seis personas
rotando.

**El collector descarta los spans de health check.** Cada contenedor se sondea
cada diez segundos, para siempre, y en X-Ray eso se paga por traza. La regla
esta en un solo sitio y vale para los dos lenguajes.
