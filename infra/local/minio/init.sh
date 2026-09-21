#!/bin/sh
# Crea los buckets que WearHack espera encontrar. Lo corre un contenedor de
# un solo uso al levantar el entorno.
set -e

echo "Esperando a MinIO..."
until mc alias set local "${S3_ENDPOINT}" "${S3_ACCESS_KEY}" "${S3_SECRET_KEY}" >/dev/null 2>&1; do
  sleep 1
done

for bucket in "${S3_BUCKET_PRENDAS}" "${S3_BUCKET_ROSTROS}"; do
  if mc ls "local/${bucket}" >/dev/null 2>&1; then
    echo "  = ${bucket} (ya existia)"
  else
    mc mb "local/${bucket}"
    echo "  + ${bucket}"
  fi
done

# Ambos buckets son privados. Las imagenes de prendas y sobre todo los recortes
# faciales son datos personales: al cliente se le sirven con URLs firmadas de
# duracion corta, nunca con lectura publica.
mc anonymous set none "local/${S3_BUCKET_PRENDAS}" >/dev/null
mc anonymous set none "local/${S3_BUCKET_ROSTROS}" >/dev/null

echo "Buckets listos."
