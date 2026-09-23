# ADR 0001: Monorepo en una organizacion privada

- **Estado:** aceptado
- **Fecha:** 2026-09-22

## Contexto

Somos seis generalistas que rotamos entre el cliente, siete servicios y la
infraestructura. Un cambio de contrato toca a la vez el backend y el cliente.

## Decision

Todo vive en un unico repositorio privado de una GitHub Organization: cliente
Flutter, gateway, cuatro servicios Spring Boot, dos FastAPI e infra.

Las revisiones se reparten con CODEOWNERS por ruta, con equipos que no son
propiedad exclusiva sino "que alguien que conozca la zona mire esto".

## Consecuencias

Un cambio de contrato entra en un solo PR y se revisa entero. No hay que
sincronizar versiones entre repos ni coordinar merges.

A cambio, el repositorio crece y hay que evitar construirlo entero en cada PR.
Eso lo resuelve [ADR 0014](0014-ci-con-path-filters-por-servicio.md).

Si algun dia un servicio necesita su propio ciclo de vida, extraerlo es un
trabajo real. Asumimos ese coste futuro a cambio de velocidad hoy.
