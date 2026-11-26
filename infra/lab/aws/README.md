# infra/lab/aws — El monolito en una EC2 del Learner Lab

Issues: #60 (host EC2), #20 (Caddy y HTTPS), #21 (Cognito en el Core), #47 (imagenes en GHCR),
#36 (jobs batch).

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
| `desplegar.sh` | EC2, timer | Pull de `develop`, `.env` desde SSM, `compose pull` de GHCR (o build), rollback. Instala los jobs |
| `correr-jobs.sh`, `systemd/wearhack-jobs.*` | EC2, timer | Jobs batch con la imagen desplegada: ranking de prendas puente, ajuste de preferencias, recalibracion |
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

## Jobs batch (#36)

`jobs-recomendador` y `jobs-colorimetria` son la imagen del servicio con otro comando (profile
`jobs`, sin puertos) y se conectan con `MONGODB_URI_JOBS` (usuario `wh_jobs`).
`correr-jobs.sh` los corre en orden y anota `OK` o `FALLO` de cada uno. El timer
`wearhack-jobs` lo lanza a las 07:00 UTC y, como la EC2 casi nunca esta encendida a esa
hora, al encenderla si se perdio la corrida: al inicio de cada ventana de prueba.
`desplegar.sh` instala el script y el timer, asi que una EC2 ya creada los recibe con el
siguiente despliegue.

La recalibracion (#37) necesita el conjunto fijo de evaluacion en
`/opt/wearhack/evaluacion/conjunto.json`; sin el, descarta la version nueva y no publica nada.

```bash
sudo /opt/wearhack/correr-jobs.sh                          # todos, ya
sudo /opt/wearhack/correr-jobs.sh ranking_prendas_puente   # solo uno
journalctl -u wearhack-jobs -n 50                          # la ultima corrida
systemctl list-timers wearhack-jobs                        # la proxima
```

## Trazas (OpenTelemetry y Jaeger)

Core, colorimetria, recomendador y los jobs mandan sus trazas por OTLP a `jaeger`, que las
guarda en memoria: se pierden al reiniciar el contenedor o la EC2, y en el lab basta.
Jaeger no publica puertos: su API de consulta (v3) se ve en `https://<dominio>/trazabilidad/api/`,
detras del mismo usuario y clave que la pagina de trazabilidad.

La pagina vive fuera del repo y se copia a `/opt/wearhack/trazabilidad/`. Caddy la sirve en
`/trazabilidad/`. El usuario y el hash de la clave salen de SSM; sin ellos la ruta queda
cerrada con una clave al azar. Para ponerlos (en CloudShell, la clave no queda en el historial):

```bash
pip install --user -q bcrypt
read -rp 'Usuario: ' U && read -rsp 'Clave: ' P && echo && H=$(python3 -c 'import bcrypt,sys;print(bcrypt.hashpw(sys.argv[1].encode(),bcrypt.gensalt(12)).decode())' "$P") && aws ssm put-parameter --name /wearhack/TRAZABILIDAD_USUARIO --type String --value "$U" --overwrite >/dev/null && aws ssm put-parameter --name /wearhack/TRAZABILIDAD_HASH --type SecureString --value "$H" --overwrite >/dev/null && unset P H && echo TRAZABILIDAD OK
```

Se aplican con el siguiente despliegue (`sudo FORZAR=1 /opt/wearhack/desplegar.sh`).

## Operar

```bash
aws ssm start-session --target <instance-id>     # sin puerto 22
journalctl -u wearhack-desplegar -n 50           # historial: OK / FALLO / esperando imagenes
sudo FORZAR=1 /opt/wearhack/desplegar.sh         # redesplegar ya
```

Al reiniciar el lab, la IP es la misma y los contenedores arrancan solos.

## Pendiente

- Nada de esta parte. La arquitectura objetivo (ECS con `cd.yml`) pide una cuenta propia.
