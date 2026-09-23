# ADR 0017: Las dependencias transitivas de Python no estan fijadas

- **Estado:** pendiente
- **Fecha:** 2026-09-22

## Contexto

`pyproject.toml` fija las dependencias directas con version exacta. Lo que ellas
arrastran, no. `uv` genera un `uv.lock` que lo resolveria, pero los Dockerfiles
y CI instalan desde `pyproject.toml` y nadie lo lee.

## Decision

Por ahora, **sin lock**. `uv.lock` esta en `.gitignore` para no commitear un
archivo que parece autoritativo sin serlo.

## Consecuencias

Un build de hoy y otro del mes que viene pueden traer versiones transitivas
distintas. Para un esqueleto es asumible; para produccion no lo es.

Cerrar el hueco significa pasar a `uv sync`, lo que cambia la estrategia de
capas del Dockerfile: hoy la capa de dependencias se reaprovecha mientras
`pyproject.toml` no cambie.

Este ADR queda **pendiente** a proposito. Cuando se decida, se actualiza a
aceptado con la opcion elegida, o se sustituye por otro.
