#!/bin/bash
# En la EC2. Sigue la rama develop de WearHack/WearHack: si hay commit nuevo (o FORZAR=1),
# actualiza el checkout y levanta el compose con las imagenes de ese commit, que publica
# en GHCR el workflow imagenes-lab.yml (#47). Si no aparecen en 30 minutos, o no hay
# token de GHCR, las construye en el host. Si el Core no queda healthy, vuelve al commit
# anterior. Lo lanza el timer wearhack-desplegar cada 5 minutos.
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
SERVICIOS=(core colorimetria recomendador)
ESPERA_IMAGENES=1800
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
# Imagenes: las de GHCR si ya estan publicadas para este commit. Si aun no, se espera
# al siguiente turno del timer; pasado ESPERA_IMAGENES (o con FORZAR) se construyen aqui.
MODO=build
TOKEN_GHCR=$(leer GHCR_TOKEN)
USUARIO_GHCR=$(leer GHCR_USER)
if [ -n "$TOKEN_GHCR" ] && [ -n "$USUARIO_GHCR" ]; then
  printf '%s' "$TOKEN_GHCR" | docker login ghcr.io -u "$USUARIO_GHCR" --password-stdin >/dev/null 2>&1 || true
  publicadas=1
  for s in "${SERVICIOS[@]}"; do
    docker manifest inspect "ghcr.io/wearhack/wearhack-$s:$NUEVO" >/dev/null 2>&1 || { publicadas=0; break; }
  done
  if [ "$publicadas" = 1 ]; then
    MODO=pull
  elif [ "${FORZAR:-0}" != "1" ] &&        [ $(( $(date +%s) - $(git_ log -1 --format=%ct "$NUEVO") )) -lt "$ESPERA_IMAGENES" ]; then
    log "esperando las imagenes de ${NUEVO:0:7} en GHCR"
    docker logout ghcr.io >/dev/null 2>&1 || true
    exit 0
  else
    log "sin imagenes de ${NUEVO:0:7} en GHCR: se construyen en el host"
  fi
fi

log "desplegando $RAMA ${ANTES:0:7} -> ${NUEVO:0:7} ($MODO)"
git_ reset --quiet --hard "$NUEVO"

# Si el commit trae otra version de este script, se corre esa (con lo que ya se trajo).
if ! cmp -s "$AWS_DIR/desplegar.sh" "$BASE/desplegar.sh" && [ -z "${REEJECUTADO:-}" ]; then
  install -m 755 "$AWS_DIR/desplegar.sh" "$BASE/desplegar.sh"
  log "desplegar.sh cambio, se relanza"
  exec 9>&-
  ANTES_DESPLIEGUE=$ANTES REEJECUTADO=1 FORZAR=1 exec "$BASE/desplegar.sh"
fi
# Tras relanzarse, el checkout ya esta en el commit nuevo: el anterior es el de antes.
ANTES=${ANTES_DESPLIEGUE:-$ANTES}

# El compose y el Caddyfile se copian a la raiz del checkout: sus rutas de build
# (./services/...) son relativas a ella. Quedan fuera de git por info/exclude.
for f in docker-compose.aws.yml Caddyfile; do cp "$AWS_DIR/$f" "$REPO/$f"; done
grep -qx '/docker-compose.aws.yml' "$REPO/.git/info/exclude" 2>/dev/null || \
  printf '/docker-compose.aws.yml\n/Caddyfile\n/.env\n' >> "$REPO/.git/info/exclude"

# Carpeta de la pagina de trazabilidad (fuera del repo). Caddy la monta en solo lectura.
mkdir -p "$BASE/trazabilidad"

TOKEN=$(curl -fsS -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 300')
IP=$(curl -fsS -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)
DB=$(leer MONGODB_DB); DB=${DB:-wearhack}
CUENTA=$(aws sts get-caller-identity --query Account --output text)
umask 077
{
  echo "DOMINIO=$(echo "$IP" | tr . -).sslip.io"
  echo "MONGODB_DB=$DB"
  echo "S3_BUCKET_PRENDAS=wearhack-prendas-$CUENTA"
  echo "IMAGEN_TAG=$NUEVO"
  for n in MONGODB_URI_CORE MONGODB_URI_COLORIMETRIA MONGODB_URI_RECOMENDACION MONGODB_URI_JOBS; do
    v=$(leer "$n")
    [ -n "$v" ] && v=$(con_base "$v" "$DB")
    echo "$n=$v"
  done
  # Pagina de trazabilidad (Caddy, basic_auth). Sin clave en SSM queda cerrada con el
  # hash de una clave al azar que nadie conoce: Caddy no arranca con el hash vacio.
  tu=$(leer TRAZABILIDAD_USUARIO); th=$(leer TRAZABILIDAD_HASH)
  if [ -z "$th" ]; then
    tu=cerrado
    th=$(docker run --rm caddy:2.10.2 caddy hash-password --plaintext "$(openssl rand -hex 24)")
  fi
  echo "TRAZABILIDAD_USUARIO=${tu:-wearhack}"
  # Entre comillas simples: el hash bcrypt lleva '$' y compose lo interpolaria.
  echo "TRAZABILIDAD_HASH='$th'"
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

levantar() {
  if [ "$MODO" = pull ]; then
    "${COMPOSE[@]}" pull --quiet "${SERVICIOS[@]}" &&       "${COMPOSE[@]}" up -d --no-build --remove-orphans
  else
    "${COMPOSE[@]}" up -d --build --remove-orphans
  fi
}

# Los jobs batch (#36): correr-jobs.sh y su timer viven en el repo. Se instalan o
# actualizan tras cada despliegue bueno, asi una EC2 ya creada los recibe sola.
instalar_jobs() {
  install -m 755 "$AWS_DIR/correr-jobs.sh" "$BASE/correr-jobs.sh"
  local cambio=0 f
  for f in "$AWS_DIR"/systemd/*; do
    cmp -s "$f" "/etc/systemd/system/$(basename "$f")" && continue
    install -m 644 "$f" /etc/systemd/system/
    cambio=1
  done
  if [ "$cambio" = 1 ]; then
    systemctl daemon-reload
    systemctl enable --now wearhack-jobs.timer
    log "timer de jobs instalado"
  fi
}

# Si el commit solo cambia el Caddyfile, compose no recrea Caddy y este sigue con la
# configuracion vieja en memoria (el archivo montado si cambia). Recargar es seguro:
# si la configuracion nueva no es valida, Caddy la rechaza y se queda con la anterior.
recargar_caddy() {
  "${COMPOSE[@]}" exec -T caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile     >/dev/null 2>&1 || log "Caddy no recargo el Caddyfile"
}

cd "$REPO"
if levantar && sano; then
  recargar_caddy
  docker logout ghcr.io >/dev/null 2>&1 || true
  log "OK ${NUEVO:0:7}"
  install -m 755 "$AWS_DIR/desplegar.sh" "$BASE/desplegar.sh"
  instalar_jobs
  # Las imagenes de commits viejos se acumulan: fuera las que nadie usa hace 3 dias.
  docker image prune -af --filter until=72h >/dev/null
  exit 0
fi
log "FALLO ${NUEVO:0:7}, vuelvo a ${ANTES:0:7}"
echo "$NUEVO" > "$BASE/.fallido"
git_ reset --quiet --hard "$ANTES"
for f in docker-compose.aws.yml Caddyfile; do cp "$AWS_DIR/$f" "$REPO/$f"; done
sed -i "s/^IMAGEN_TAG=.*/IMAGEN_TAG=$ANTES/" "$REPO/.env"
# Las imagenes del commit anterior ya estan en el host (descargadas o construidas).
"${COMPOSE[@]}" up -d --no-build --remove-orphans || "${COMPOSE[@]}" up -d --build --remove-orphans || true
recargar_caddy
docker logout ghcr.io >/dev/null 2>&1 || true
exit 1
