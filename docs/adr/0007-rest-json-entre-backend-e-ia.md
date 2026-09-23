# ADR 0007: REST/JSON entre los servicios de negocio y los de IA

- **Estado:** aceptado
- **Fecha:** 2026-09-22

## Contexto

Los servicios Spring Boot llaman a los de FastAPI. Las opciones eran REST sobre
JSON o gRPC.

## Decision

REST sobre JSON. **gRPC queda documentado como posible migracion futura y no se
implementa.**

## Consecuencias

Se depura con `curl` y se lee en los logs sin herramientas extra, que es lo que
importa cuando seis personas rotan entre servicios.

No hay `.proto` que generar ni mantener sincronizado entre Java y Python, ni un
paso de codegen en el build.

A cambio, JSON serializa mas lento y pesa mas que protobuf, y no hay contrato
tipado que rompa el build cuando alguien cambia un campo.

Cuando el volumen lo justifique, migrar significa introducir `.proto`, codegen
en los dos lenguajes y una transicion con los dos protocolos conviviendo. El
momento de revisarlo es cuando la latencia de estas llamadas aparezca en las
trazas como algo que pesa.
