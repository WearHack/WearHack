#!/usr/bin/env sh
# Verificacion al inicio de una ventana de prueba del Learner Lab (#52).
#
#   infra/lab/verificar-ventana.sh <dominio>
#   TOKEN=<access token de Cognito> infra/lab/verificar-ventana.sh <dominio>
#
# Se corre en el host, desde la carpeta del compose. Solo lee: no levanta ni para nada.
# Sale con 1 si algo falla, para poder usarlo en un cron o a mano.

set -u

DOMINIO="${1:-}"
fallos=0

ok()    { printf '  ok    %s\n' "$1"; }
falla() { printf '  FALLA %s\n' "$1"; fallos=$((fallos + 1)); }

echo "Contenedores"
for servicio in core colorimetria recomendador; do
  id=$(docker compose ps -q "$servicio" 2>/dev/null)
  if [ -z "$id" ]; then
    falla "$servicio no esta corriendo"
    continue
  fi
  estado=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}sin-healthcheck{{end}}' "$id")
  if [ "$estado" = "healthy" ]; then ok "$servicio healthy"; else falla "$servicio $estado"; fi
done

if [ -z "$DOMINIO" ]; then
  echo "Sin dominio: no se comprueba HTTPS ni el JWT."
else
  echo "HTTPS (Caddy)"
  # Sin -k: un certificado invalido o autofirmado tiene que fallar aqui.
  if curl -fsS -o /dev/null "https://$DOMINIO/health"; then
    ok "https://$DOMINIO/health con certificado valido"
  else
    falla "https://$DOMINIO/health no responde o el certificado no es valido"
  fi

  echo "JWT en el Core"
  codigo=$(curl -s -o /dev/null -w '%{http_code}' "https://$DOMINIO/api/v1/usuarios/me")
  if [ "$codigo" = "401" ]; then ok "sin token: 401"; else falla "sin token: $codigo (se esperaba 401)"; fi

  if [ -n "${TOKEN:-}" ]; then
    codigo=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TOKEN" \
      "https://$DOMINIO/api/v1/usuarios/me")
    # 404 tambien vale: el token es valido y el usuario aun no completo el registro.
    case "$codigo" in
      200|404) ok "con token: $codigo" ;;
      *) falla "con token: $codigo" ;;
    esac
  else
    echo "  --    sin TOKEN: no se prueba un JWT valido"
  fi
fi

echo "Disco"
uso=$(df -P / | awk 'NR==2 {gsub("%", "", $5); print $5}')
if [ "$uso" -lt 85 ]; then ok "disco al ${uso}%"; else falla "disco al ${uso}%"; fi

if [ "$fallos" -gt 0 ]; then
  echo "$fallos comprobacion(es) fallaron."
  exit 1
fi
echo "Todo en orden."
