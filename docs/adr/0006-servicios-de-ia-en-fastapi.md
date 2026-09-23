# ADR 0006: Los servicios de IA en FastAPI

- **Estado:** aceptado
- **Fecha:** 2026-09-22

## Contexto

`colorimetria` clasifica la temporada de color a partir del recorte facial.
`recomendador` genera outfits. Los dos necesitan el ecosistema numerico de
Python, que en la JVM no tiene equivalente comodo.

## Decision

Dos servicios FastAPI asincronos sobre Python 3.12, con `uvicorn` y sus
extensiones `uvloop` y `httptools`.

Los modulos de health, telemetria, logs y arranque de jobs son **identicos** en
los dos, por copia.

Los endpoints stub devuelven 501, no datos de ejemplo.

## Consecuencias

Python 3.12 y no 3.14 porque MediaPipe y parte del stack numerico todavia no
publican ruedas estables para esa version.

Devolver 501 evita que alguien monte el cliente encima de datos inventados y
descubra el error mucho mas tarde y mucho mas caro.

La duplicacion entre los dos servicios es consciente: una libreria compartida
anadiria una dependencia de build y romperia los path filters. Con dos servicios
sale mas barato duplicar. Con un tercero, conviene reconsiderarlo.

Dos lenguajes en el backend significa dos toolchains, dos formas de instrumentar
y dos conjuntos de convenciones que el equipo debe conocer.
