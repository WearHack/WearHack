# infra/lab/aws — El monolito en una EC2 del Learner Lab

Issues: #60 (host EC2), #20 (Caddy y HTTPS), #21 (Cognito en el Core), #47 (imagenes en GHCR).

Una EC2 con Docker Compose corre `core`, `colorimetria` y `recomendador`, con Caddy
delante (TLS automatico sobre `sslip.io`). Mongo es Atlas. La EC2 sigue `develop`: cada
5 minutos mira si hay commit nuevo y baja de GHCR las imagenes de ese commit, que publica
`.github/workflows/imagenes-lab.yml` en cada push a `develop`. Si no aparecen en 30
minutos (o no hay token de GHCR), las construye en el host. Si el Core no queda healthy,
vuelve al commit anterior.

No se usa `cd.yml` (ECS): en el Learner Lab no se puede crear el rol OIDC para GitHub y
las credenciales caducan cada ~4 horas. El pull desde la EC2 no necesita credenciales de
AWS en GitHub.

## Archivos

| Archivo | Corre en | Hace |
|---|---|---|
| `secretos.sh` | CloudShell | URIs de Atlas a SSM (SecureString) y borra el archivo |
| `cognito.sh` | CloudShell | User Pool y app client; IDs a SSM |
| `crear-host.sh` | CloudShell | Bucket de prendas, security group (80/443, sin 22), EC2 t3.large, IP elastica |
| `instalar-host.sh` | EC2, user-data | Docker, Compose, git, clona el repo, timer, primer despliegue |
| `desplegar.sh` | EC2, timer | Pull de `develop`, `.env` desde SSM, `compose pull` de GHCR (o build), rollback |
| `docker-compose.aws.yml`, `Caddyfile` | EC2 | Servicios y proxy. Solo Caddy publica puertos |

Las imagenes de prendas van a `wearhack-prendas-<cuenta>` (privado, solo URLs firmadas).
El Core entra con el rol de la EC2 (`LabRole`), sin claves.

Atlas da las URIs sin base y el Core la exige (`Database name must not be empty`):
`desplegar.sh` le agrega `/<MONGODB_DB>`.

## Montarlo

En CloudShell, desde esta carpeta:

1. `.envBasesDeDatos` en `~` y `bash secretos.sh`.
2. Token de GitHub (fine-grained, owner `WearHack`, solo este repo, Contents read-only):
   ```bash
   read -rsp 'Token: ' T && aws ssm put-parameter --name /wearhack/GITHUB_TOKEN --type SecureString --value "$T" --overwrite >/dev/null && unset T && echo && echo TOKEN OK
   ```
3. Token *classic* de GitHub con **solo** `read:packages`, para bajar las imagenes de GHCR
   (los fine-grained no sirven para GHCR). Sin el, la EC2 construye en el host:
   ```bash
   read -rsp 'Token GHCR: ' T && aws ssm put-parameter --name /wearhack/GHCR_TOKEN --type SecureString --value "$T" --overwrite >/dev/null && aws ssm put-parameter --name /wearhack/GHCR_USER --type String --value <tu-usuario-de-github> --overwrite >/dev/null && unset T && echo && echo GHCR OK
   ```
4. `bash cognito.sh` (lo que imprime va en el `--dart-define` de la app).
5. `bash crear-host.sh` y agregar la IP en Atlas → Network Access.
6. ~10 minutos despues: `/health` da 200 y `/api/v1/usuarios/me` da 401.

## Operar

```bash
aws ssm start-session --target <instance-id>     # sin puerto 22
journalctl -u wearhack-desplegar -n 50           # historial: OK / FALLO / esperando imagenes
sudo FORZAR=1 /opt/wearhack/desplegar.sh         # redesplegar ya
```

Al reiniciar el lab, la IP es la misma y los contenedores arrancan solos.

## Pendiente

- Nada de esta parte. La arquitectura objetivo (ECS con `cd.yml`) pide una cuenta propia.
