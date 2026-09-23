# ADR 0003: Un solo proyecto Flutter para Android, iOS y Web

- **Estado:** aceptado
- **Fecha:** 2026-09-22

## Contexto

Queremos movil y web sin escribir la aplicacion dos veces, pero la web no puede
hacer lo mismo que el movil: ahi no hay camara utilizable ni acelerador para los
modelos de [ADR 0002](0002-clasificacion-de-prendas-on-device.md).

## Decision

Un unico proyecto Flutter con los tres targets. Movil es la prioridad. **Web es
solo consulta y gestion.**

El codigo de captura vive detras de `lib/platform/captura.dart`, que elige
implementacion con un import condicional. La rama por defecto es la de web; la
de movil entra solo cuando existe `dart:io`.

## Consecuencias

El aislamiento no depende de que nadie se despiste: la implementacion movil
importa `dart:io`, que en web no existe, asi que **un import mal colocado rompe
`flutter build web` y en ningun otro sitio**. Por eso esa build corre en CI.

Elegir web por defecto en vez de movil significa que un target nuevo pierde la
captura en lugar de no compilar.

La UI tiene que consultar `disponible` y ocultar la captura en web, en vez de
dejar que falle al pulsarla.
