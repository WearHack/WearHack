#!/bin/bash
# En CloudShell: pasa un archivo KEY=valor (por defecto ~/.envBasesDeDatos) a SSM
# Parameter Store como SecureString bajo /wearhack/ y lo borra. No imprime ningun valor.
#
# Claves que lee desplegar.sh: MONGODB_DB, MONGODB_URI_CORE, MONGODB_URI_COLORIMETRIA,
# MONGODB_URI_RECOMENDACION, MONGODB_URI_JOBS. El token de GitHub va aparte (README).
set -euo pipefail
ARCHIVO=${1:-~/.envBasesDeDatos}
[ -f "$ARCHIVO" ] || { echo "Falta $ARCHIVO"; exit 1; }
while IFS= read -r linea || [ -n "$linea" ]; do
  linea=${linea%$'\r'}
  [[ -z "$linea" || "$linea" == \#* || "$linea" != *=* ]] && continue
  nombre=${linea%%=*}
  valor=${linea#*=}
  valor=${valor%\"}; valor=${valor#\"}
  [ -z "$valor" ] && { echo "$nombre vacio, se salta"; continue; }
  aws ssm put-parameter --name "/wearhack/$nombre" --type SecureString --value "$valor" --overwrite >/dev/null
  echo "$nombre guardado"
done < "$ARCHIVO"
shred -u "$ARCHIVO" 2>/dev/null || rm -f "$ARCHIVO"
echo "SECRETOS OK"
