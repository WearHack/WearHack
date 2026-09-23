# ADR 0009: MongoDB Atlas en AWS, no DocumentDB

- **Estado:** aceptado
- **Fecha:** 2026-09-22

## Contexto

[ADR 0008](0008-mongodb-con-documentos-embebidos.md) apoya la integridad de los
datos en `$jsonSchema`. La opcion gestionada obvia dentro de AWS es DocumentDB.

## Decision

**MongoDB Atlas.** DocumentDB no soporta validacion con `$jsonSchema` y tiene
huecos en el pipeline de agregacion.

## Consecuencias

El esquema se valida donde deben validarse los datos: en la base. Si usaramos
DocumentDB habria que mover esa validacion a la capa de aplicacion, repetirla en
Java y en Python, y confiar en que nadie escriba por otro camino.

A cambio, Atlas es un proveedor mas que contratar y pagar aparte, fuera de la
factura de AWS, con su propia gestion de accesos y su propio peering hacia la
VPC.

Si algun dia se prefiere DocumentDB por consolidar proveedores, hay que
replantear la validacion antes, no despues.
