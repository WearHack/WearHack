# ADR 0005: Cuatro servicios de negocio en Spring Boot

- **Estado:** aceptado
- **Fecha:** 2026-09-22

## Contexto

El dominio se parte en cuatro areas: `usuarios`, `closet`, `outfits` y
`publicidad`, esta ultima el catalogo de marcas aliadas que monetiza el producto.

## Decision

Cuatro servicios independientes en Spring Boot 3.5 sobre Java 21, cada uno con
su Dockerfile, su Actuator y su controlador placeholder.

Son **identicos entre si** salvo nombre, puerto y ruta base. La uniformidad es
deliberada.

Comparten un POM padre con las dependencias comunes, pero cada modulo se
construye tambien por separado.

## Consecuencias

Conocer uno es conocer los cuatro, que es lo que hace barata la rotacion del
equipo. Un cambio transversal se aplica cuatro veces igual.

Cada modulo construible solo es lo que permite los path filters de
[ADR 0014](0014-ci-con-path-filters-por-servicio.md). Por eso las imagenes se
construyen con `-f <servicio>/pom.xml` y no con el agregador, que exigiria que
existan los cuatro.

Cuatro servicios para seis personas es mucha superficie operativa. Lo asumimos
con los ojos abiertos.
