# ADR 0002: La clasificacion de prendas corre en el dispositivo

- **Estado:** aceptado
- **Fecha:** 2026-09-22

## Contexto

Digitalizar un closet son decenas de fotos por usuario. Cada una hay que
recortarla del fondo y deducirle tipo, textura, patron y color.

## Decision

Todo eso pasa en el telefono con LiteRT/TFLite. **No existe ni va a existir un
servicio backend de clasificacion de prendas.**

Modelos: `u2netp` para el fondo y un MobileNetV3-Small multi-head cuantizado a
INT8 para los atributos. Los interpretes se cargan **de uno en uno**.

Al backend solo sube la imagen ya procesada y los atributos. La foto original no
sale del dispositivo.

## Consecuencias

No pagamos GPU ni ancho de banda por cada foto, y el coste por usuario no crece
con el tamano de su closet. La digitalizacion funciona sin conexion.

El objetivo es gama media-baja, asi que INT8 y carga secuencial no son
optimizaciones opcionales: con los dos interpretes a la vez en memoria, los
telefonos con poca RAM matan el proceso.

Mejorar el modelo obliga a publicar una version de la app, no a desplegar un
servicio. Habra usuarios clasificando con modelos viejos durante semanas, y las
correcciones que hagan alimentan [ADR 0011](0011-jobs-batch-como-tareas-programadas-de-ecs.md).

Ver tambien [ADR 0016](0016-solo-el-recorte-facial-sale-del-dispositivo.md).
