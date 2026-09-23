# ADR 0014: CI construye solo lo que cambio

- **Estado:** aceptado
- **Fecha:** 2026-09-22

## Contexto

El monorepo de [ADR 0001](0001-monorepo-en-organizacion-privada.md) tiene siete
servicios y un cliente. Construirlos todos en cada PR seria una espera larga por
un cambio de una linea, y seis de cada siete builds no probarian nada.

## Decision

`dorny/paths-filter` decide que cambio, y su salida alimenta una **matriz
dinamica**. Un PR que toca `closet` lanza un solo job.

Cada servicio se reconstruye tambien cuando cambia el POM padre o el propio
workflow.

La imagen se construye en el PR, no solo al desplegar.

Hay un job final llamado `ci` que resume el resto y es **el unico check que debe
marcarse como obligatorio** en la proteccion de rama.

## Consecuencias

El tiempo de CI es proporcional al cambio, no al tamano del repo.

Marcar los siete jobs como obligatorios bloquearia la fusion cada vez que uno se
salta, que es justo lo contrario de lo que buscan los path filters. De ahi el
job resumen.

Construir la imagen en el PR cuesta minutos pero evita descubrir un Dockerfile
roto despues de fusionar.

Los filtros son una lista escrita a mano: cuando se anada un servicio, hay que
acordarse de anadirlo tambien aqui. Un servicio que falte no falla, simplemente
deja de probarse, que es peor.
