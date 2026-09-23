# ADR 0008: MongoDB con atributos embebidos

- **Estado:** aceptado
- **Fecha:** 2026-09-22

## Contexto

Una prenda tiene atributos que el modelo on-device produce de golpe y que el
recomendador lee siempre juntos. Los atributos van a crecer segun mejore el
modelo.

## Decision

MongoDB 8. **Una prenda es un documento con sus atributos embebidos**, no filas
repartidas entre tablas.

Siete colecciones base: `usuarios`, `prendas`, `outfits`, `selecciones`,
`correcciones_clasificacion`, `configuracion` y `catalogos`.

La coleccion `prendas` lleva validacion `$jsonSchema` estricta con enums, y el
color como Lab numerico mas categoria.

Indice compuesto `usuario_id + slot_outfit + atributos.clima_apto`, en ese orden
por la regla ESR.

## Consecuencias

Leer un closet entero no necesita joins. Anadir un atributo no obliga a migrar
nada, porque `additionalProperties` queda abierto.

Lab y no RGB porque ahi la distancia entre colores se parece a la que percibe el
ojo, que es lo que necesita el nearest-centroid de `colorimetria`. La categoria
es redundante a proposito: permite filtrar sin recalcular distancias.

Los enums viven aqui y en `client/lib/core/vocabulario.dart`. Si cambian, cambian
en los dos sitios, y la base rechaza lo que no cuadre.

`clima_apto` va ultimo en el indice porque es un array: lo hace multikey, y
ponerlo antes inflaria las ramas a recorrer por usuario.
