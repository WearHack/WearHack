# ADR 0011: Los jobs nocturnos viven dentro de los servicios Python

- **Estado:** aceptado
- **Fecha:** 2026-09-22

## Contexto

Tres procesos nocturnos: recalibrar los centroides de color con las correcciones
de los usuarios, rankear las prendas puente de cada usuario, y ajustar el vector
de preferencias de quien tenga al menos diez selecciones nuevas.

Opciones: un servicio aparte con cron interno, una Lambda por job, o modulos
dentro de los servicios que ya tienen el codigo.

## Decision

Cada job es un modulo ejecutable dentro de su servicio:

```
python -m app.jobs.recalibrar_centroides
python -m app.jobs.ranking_prendas_puente
python -m app.jobs.ajuste_preferencias
```

En AWS corren con la **misma imagen** del servicio y distinto comando, lanzados
por EventBridge Scheduler como ECS Scheduled Tasks.

## Consecuencias

No hay una segunda imagen que mantener ni un contenedor encendido toda la noche
sin hacer nada. El job comparte configuracion, acceso a datos y telemetria con
su servicio, asi que no hay dos formas de leer lo mismo.

Descartamos Lambda porque la recalibracion de centroides puede pasar de quince
minutos y duplicaria las dependencias numericas.

Cada job emite su propia traza con el nombre `<servicio>-jobs` y sale con codigo
0 o 1, que es lo que ECS mira para saber si la tarea termino bien.

El umbral de diez selecciones no es arbitrario: por debajo, el ruido pesa mas
que la senal y el vector oscilaria de un dia para otro.
