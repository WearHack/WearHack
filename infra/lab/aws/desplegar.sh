#!/bin/bash
# En la EC2. Sigue la rama develop de WearHack/WearHack: si hay commit nuevo (o FORZAR=1),
# actualiza el checkout y reconstruye con docker compose. Si el Core no queda healthy,
# vuelve al commit anterior. Lo lanza el timer wearhack-desplegar cada 5 minutos.
#
# Vive copiado en /opt/wearhack/desplegar.sh; tras cada despliegue bueno se reemplaza
# por la version del repo, asi que los cambios a este archivo tambien llegan solos.
set -euo pipefail
exec 9>/var/lock/wearhack-desplegar.lock
flock -n 9 || { echo "ya hay un despliegue en curso"; exit 0; }

BASE=/opt/wearhack
REPO=$BASE/repo
AWS_DIR=$REPO/infra/lab/aws
RAMA=${RAMA:-develop}
URL=https://github.com/WearHack/WearHack.git
COMPOSE=(docker compose -p wearhack -f docker-compose.aws.yml)
R=us-east-1
log() { echo "$(date -u +%FT%TZ) $*"; }
leer() { aws ssm get-parameter --region $R --name "/wearhack/$1" --with-decryption \
  --query Parameter.Value --output text 2>/dev/null || true; }

# Atlas entrega la URI sin base (.../?opts). Core la exige en la ruta: se agrega MONGODB_DB.
con_base() {
  local u=$1 db=$2 pre q=""
  pre=${u%%\?*}
  [[ $u == *\?* ]] && q="?${u#*\?}"
  local tras=${pre#*://}; tras=${tras##*@}
  if [[ $tras != */* ]]; then pre="$pre/$db"
  elif [[ -z ${tras#*/} ]]; then pre="$pre$db"; fi
  echo "$pre$q"
}

TOKEN_GH=$(leer GITHUB_TOKEN)
[ -n "$TOKEN_GH" ] || { log "falta /wearhack/GITHUB_TOKEN en SSM"; exit 1; }
# El token va solo en la cabecera de cada comando git: nunca queda en .git/config.
AUTH="Authorization: Basic $(printf 'x-access-token:%s' "$TOKEN_GH" | base64 -w0)"
git_() { git -c http.extraHeader="$AUTH" -C "$REPO" "$@"; }

if [ ! -d "$REPO/.git" ]; then
  git -c http.extraHeader="$AUTH" clone --quiet --branch "$RAMA" "$URL" "$REPO"
  FORZAR=1
fi
ANTES=$(git_ rev-parse HEAD)
git_ fetch --quiet origin "$RAMA"
NUEVO=$(git_ rev-parse "origin/$RAMA")
if [ "${FORZAR:-0}" != "1" ]; then
  [ "$ANTES" = "$NUEVO" ] && exit 0
  # Un commit que ya fallo no se reintenta cada 5 minutos: espera al siguiente.
  [ "$(cat "$BASE/.fallido" 2>/dev/null)" = "$NUEVO" ] && exit 0
fi
log "desplegando $RAMA ${ANTES:0:7} -> ${NUEVO:0:7}"
git_ reset --quiet --hard "$NUEVO"

# El compose y el Caddyfile se copian a la raiz del checkout: sus rutas de build
# (./services/...) son relativas a ella. Quedan fuera de git por info/exclude.
for f in docker-compose.aws.yml Caddyfile; do cp "$AWS_DIR/$f" "$REPO/$f"; done
grep -qx '/docker-compose.aws.yml' "$REPO/.git/info/exclude" 2>/dev/null || \
  printf '/docker-compose.aws.yml\n/Caddyfile\n/.env\n' >> "$REPO/.git/info/exclude"

TOKEN=$(curl -fsS -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 300')
IP=$(curl -fsS -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)
DB=$(leer MONGODB_DB); DB=${DB:-wearhack}
umask 077
{
  echo "DOMINIO=$(echo "$IP" | tr . -).sslip.io"
  echo "MONGODB_DB=$DB"
  for n in MONGODB_URI_CORE MONGODB_URI_COLORIMETRIA MONGODB_URI_RECOMENDACION MONGODB_URI_JOBS; do
    v=$(leer "$n")
    [ -n "$v" ] && v=$(con_base "$v" "$DB")
    echo "$n=$v"
  done
  # IDs del User Pool (no son secretos): de SSM (cognito.sh) o de cognito.env.
  for n in COGNITO_REGION COGNITO_USER_POOL_ID COGNITO_CLIENT_IDS; do
    v=$(leer "$n")
    [ -z "$v" ] && [ -f "$BASE/cognito.env" ] && v=$(sed -n "s/^$n=//p" "$BASE/cognito.env")
    echo "$n=$v"
  done
} > "$REPO/.env"
umask 022

sano() {
  for _ in $(seq 1 36); do
    [ "$(docker inspect -f '{{.State.Health.Status}}' wearhack-core-1 2>/dev/null)" = healthy ] && return 0
    sleep 5
  done
  return 1
}

cd "$REPO"
if "${COMPOSE[@]}" up -d --build --remove-orphans && sano; then
  log "OK ${NUEVO:0:7}"
  install -m 755 "$AWS_DIR/desplegar.sh" "$BASE/desplegar.sh"
  docker image prune -f >/dev/null
  exit 0
fi
log "FALLO ${NUEVO:0:7}, vuelvo a ${ANTES:0:7}"
echo "$NUEVO" > "$BASE/.fallido"
git_ reset --quiet --hard "$ANTES"
for f in docker-compose.aws.yml Caddyfile; do cp "$AWS_DIR/$f" "$REPO/$f"; done
"${COMPOSE[@]}" up -d --build --remove-orphans || true
exit 1
