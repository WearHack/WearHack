#!/usr/bin/env bash
# Falla si hay imagenes en carpetas de pruebas que no esten en la lista blanca (#46).
#
#   .github/scripts/sin-fotos-en-pruebas.sh
#
# Lo corre el job "Sin fotos en las pruebas" de ci.yml, y se puede correr en local
# desde la raiz del repo. Solo mira archivos versionados (git ls-files).

set -euo pipefail

LISTA=.github/sinteticos-permitidos.txt

# Rutas permitidas: sin comentarios ni lineas vacias.
permitidas=$(sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$LISTA" | sort -u)

encontradas=$(git ls-files \
  | grep -iE '\.(jpe?g|png|heic|heif|webp|bmp|tiff?)$' \
  | grep -E '(^|/)(tests?|test_data|fixtures|src/test)/' \
  | sort -u || true)

prohibidas=$(comm -23 <(printf '%s\n' "$encontradas") <(printf '%s\n' "$permitidas") | sed '/^$/d')

if [ -n "$prohibidas" ]; then
  echo "Imagenes en carpetas de pruebas que no estan en $LISTA:"
  printf '  %s\n' "$prohibidas"
  echo "Los tests no usan fotos reales: genera la imagen en el test o, si es sintetica,"
  echo "anadela a $LISTA con su motivo."
  exit 1
fi

echo "Sin imagenes no permitidas en las pruebas."
