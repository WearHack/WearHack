#!/bin/bash
# En la EC2. Corre los jobs batch del lab (#36), uno detras de otro, con la imagen del
# commit desplegado. Lo lanza el timer wearhack-jobs (una vez al dia, y al encender la
# EC2 si se perdio la corrida) o se corre a mano:
#   sudo /opt/wearhack/correr-jobs.sh                       # todos
#   sudo /opt/wearhack/correr-jobs.sh ranking_prendas_puente  # solo ese
#
# Cada job deja su linea de corrida (job, umbral_alcanzado, usuarios_afectados,
# timestamp); aqui se anota OK o FALLO de cada uno. Un job que falla no frena a los
# demas, pero la unidad queda en failed para que se vea en systemctl.
set -uo pipefail

BASE=/opt/wearhack
REPO=$BASE/repo
COMPOSE=(docker compose -p wearhack -f docker-compose.aws.yml --profile jobs)
log() { echo "$(date -u +%FT%TZ) $*"; }

# servicio:modulo, en orden. La recalibracion va antes de la desvinculacion del Core
# (08:30 UTC), que consume lo que la recalibracion marco.
JOBS=(
  jobs-recomendador:ranking_prendas_puente
  jobs-recomendador:ajuste_preferencias
  jobs-colorimetria:recalibrar_centroides
)

# Mismo candado que desplegar.sh: no se corre un job mientras cambian los contenedores,
# y el despliegue espera al siguiente turno del timer si hay jobs corriendo.
exec 9>/var/lock/wearhack-desplegar.lock
flock -w 1800 9 || { log "el despliegue no solto el candado en 30 minutos"; exit 1; }

cd "$REPO"
[ -f .env ] || { log "falta $REPO/.env: aun no hay despliegue"; exit 1; }
mkdir -p "$BASE/evaluacion"
[ -f "$BASE/evaluacion/conjunto.json" ] && export RUTA_CONJUNTO_EVALUACION=/evaluacion/conjunto.json

fallidos=0
for job in "${JOBS[@]}"; do
  servicio=${job%%:*}
  modulo=${job#*:}
  [ $# -gt 0 ] && [[ " $* " != *" $modulo "* ]] && continue
  log "corre $modulo"
  extra=()
  [ -n "${RUTA_CONJUNTO_EVALUACION:-}" ] && [ "$servicio" = jobs-colorimetria ] && \
    extra=(-e "RUTA_CONJUNTO_EVALUACION=$RUTA_CONJUNTO_EVALUACION")
  if "${COMPOSE[@]}" run --rm --no-deps "${extra[@]}" "$servicio" python -m "app.jobs.$modulo"; then
    log "OK $modulo"
  else
    log "FALLO $modulo"
    fallidos=$((fallidos + 1))
  fi
done
[ "$fallidos" -eq 0 ]
