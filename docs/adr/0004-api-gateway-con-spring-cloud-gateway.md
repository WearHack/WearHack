# ADR 0004: Spring Cloud Gateway como entrada unica

- **Estado:** aceptado
- **Fecha:** 2026-09-22

## Contexto

El cliente no debe conocer siete servicios ni sus puertos, y la autenticacion no
puede repetirse en cada uno.

Habia dos opciones: un gateway propio en Java, o un proxy en local y Amazon API
Gateway en AWS.

## Decision

Un servicio `gateway` con Spring Cloud Gateway. **El mismo binario en local y en
Fargate**, detras de un ALB.

Rutea por path, con las URIs de destino parametrizadas por entorno. Su `/health`
no consulta a los servicios de abajo.

No hereda del POM padre de los servicios: ellos van sobre Tomcat y el gateway
sobre Netty, y mezclar los dos starters da conflictos.

## Consecuencias

No hay dos configuraciones de ruteo que mantener ni comportamiento que solo
aparece en AWS. El equipo ya sabe Java, asi que tocar un filtro no exige
aprender otra herramienta.

A cambio, es un servicio mas que desplegar y escalar, donde Amazon API Gateway
seria gestionado.

Que el health no mire hacia abajo es deliberado: si reportara caido porque
`publicidad` lo esta, un fallo ahi tumbaria el acceso a todo lo demas.

**Hueco conocido:** un servicio caido devuelve 500 y deberia ser 503. Arreglarlo
bien pide un circuit breaker.
