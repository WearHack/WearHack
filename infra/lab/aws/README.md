# infra/lab/aws — El monolito en una EC2 del Learner Lab

Issues: #60 (host EC2), #20 (Caddy y HTTPS), #21 (Cognito en el Core).

Una EC2 con Docker Compose corre `core`, `colorimetria` y `recomendador`, con Caddy
delante (TLS automatico sobre `sslip.io`). Mongo es Atlas. La EC2 sigue `develop`: cada
5 minutos mira si hay commit nuevo y reconstruye. Si el Core no queda healthy, vuelve al
commit anterior.

No se usa `cd.yml` (ECS): en el Learner Lab no se puede crear el rol OIDC para GitHub y
las credenciales caducan cada ~4 horas. El pull desde la EC2 no necesita credenciales de
AWS en GitHub.

## Archivos

| Archivo | Corre en | Hace |
|---|---|---|
| `secretos.sh` | CloudShell | URIs de Atlas a SSM (SecureString) y borra el archivo |
| `cognito.sh` | CloudShell | User Pool y app client; IDs a SSM |
| `crear-host.sh` | CloudShell | Security group (80/443, sin 22), EC2 t3.large, IP elastica |
| `instalar-host.sh` | EC2, user-data | Docker, Compose, git, clona el repo, timer, primer despliegue |
| `desplegar.sh` | EC2, timer | Pull de `develop`, `.env` desde SSM, `compose up --build`, rollback |
| `docker-compose.aws.yml`, `Caddyfile` | EC2 | Servicios y proxy. Solo Caddy publica puertos |

Atlas da las URIs sin base y el Core la exige (`Database name must not be empty`):
`desplegar.sh` le agrega `/<MONGODB_DB>`.

## Montarlo

En CloudShell, desde esta carpeta:

1. `.envBasesDeDatos` en `~` y `bash secretos.sh`.
2. Token de GitHub (fine-grained, owner `WearHack`, solo este repo, Contents read-only):
   ```bash
   read -rsp 'Token: ' T && aws ssm put-parameter --name /wearhack/GITHUB_TOKEN --type SecureString --value "$T" --overwrite >/dev/null && unset T && echo && echo TOKEN OK
   ```
3. `bash cognito.sh` (lo que imprime va en el `--dart-define` de la app).
4. `bash crear-host.sh` y agregar la IP en Atlas → Network Access.
5. ~10 minutos despues: `/health` da 200 y `/api/v1/usuarios/me` da 401.

## Operar

```bash
aws ssm start-session --target <instance-id>     # sin puerto 22
journalctl -u wearhack-desplegar -n 50           # historial: OK / FALLO
sudo FORZAR=1 /opt/wearhack/desplegar.sh         # redesplegar ya
```

Al reiniciar el lab, la IP es la misma y los contenedores arrancan solos.

## Pendiente

- Google en Cognito (#22).
- Imagenes en GHCR en vez de construir en el host (#47).
