# ADR 0010: S3 para imagenes, MinIO en local

- **Estado:** aceptado
- **Fecha:** 2026-09-22

## Contexto

Guardamos imagenes de prendas ya procesadas y recortes faciales. No caben en
Mongo ni tiene sentido meterlas ahi.

Para el entorno local habia dos candidatos: LocalStack o MinIO.

## Decision

S3 en AWS. **MinIO en local**, en `docker compose`, con dos buckets privados:
`wearhack-prendas` y `wearhack-rostros`.

## Consecuencias

MinIO arranca en un par de segundos y pesa unos cien megabytes, frente a
LocalStack que tarda mucho mas y pesa casi un giga. Como esto se levanta muchas
veces al dia, la diferencia se nota.

MinIO habla el protocolo de S3, asi que el codigo es el mismo cambiando el
endpoint.

A cambio, MinIO solo emula S3. Si mas adelante queremos emular SQS o IAM en
local, habra que anadir LocalStack o vivir sin ello.

Los dos buckets son privados. Las imagenes de prendas y sobre todo los recortes
faciales son datos personales: al cliente se le sirven con URLs firmadas de
duracion corta, nunca con lectura publica.

**MinIO ya no publica en Docker Hub.** Las imagenes salen de `quay.io`.
