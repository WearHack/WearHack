# infra/lab — Operación en el AWS Academy Learner Lab

Issues: #49 (épica de observabilidad), #50 (logs), #52 (health checks y checklist).

En el lab no hay CloudWatch, ADOT ni SNS: los logs se quedan en el host y la
verificación se hace a mano al inicio de cada ventana de prueba. Eso queda para la
arquitectura objetivo (cuenta AWS propia). Ref: `docs/stack-tecnologico-wearhack.md`
sección 8.

## Health checks

Los `HEALTHCHECK` viven en el `Dockerfile` de cada imagen y el compose los hereda:

| Servicio | Comprueba | Imagen |
|---|---|---|
| `core` | `/actuator/health/readiness` responde `UP` | `services/core/Dockerfile` |
| `colorimetria` | `/health` responde 200 | `services/colorimetria/Dockerfile` |
| `recomendador` | `/health` responde 200 | `services/recomendador/Dockerfile` |

Todos los servicios llevan `restart: unless-stopped`. Los `jobs-*` no tienen health
check: corren y terminan.

```bash
docker compose ps        # columna STATUS: (healthy)
```

## Logs (#50)

- Driver `json-file` con rotación: `max-size: 10m`, `max-file: "3"` por contenedor
  (ancla `x-logging` del `docker-compose.yml`). Como mucho ~30 MB por servicio.
- Todos los servicios escriben JSON en stdout. Cada corrida de job deja una línea con
  `job`, `estado`, `umbral_alcanzado`, `usuarios_afectados` y `timestamp`.
- Ningún log lleva el cuerpo de una petición ni imágenes (#51, `app/errores.py`).

Consulta desde tu máquina, sin abrir el puerto 22, vía SSM:

```bash
aws ssm start-session --target <instance-id>
# ya dentro del host:
cd /opt/wearhack
docker compose logs --since 1h core
docker compose logs jobs-recomendador | grep '"job"'
docker compose logs core | jq 'select(.nivel=="ERROR")'
```

## MongoDB Atlas

Cada componente entra con su usuario (`infra/datos/README.md`). En el `.env` del host:

```
MONGODB_DB=wearhack
MONGODB_URI_CORE=
MONGODB_URI_COLORIMETRIA=
MONGODB_URI_RECOMENDACION=
MONGODB_URI_JOBS=
```

Cada URI lleva la base en la ruta (`...mongodb.net/wearhack?...`). Si una está vacía,
ese servicio usa `MONGO_URI` (el Mongo local del compose).

## Checklist de cada ventana de prueba

1. **Start Lab** en AWS Academy y esperar el círculo verde. Las credenciales
   temporales cambian en cada sesión.
2. **Arrancar la EC2** (EC2 → Instances → Start). La IP elástica debe seguir asociada.
3. **Entrar por SSM** (`aws ssm start-session --target <instance-id>`).
4. **Levantar** si no está arriba: `docker compose up -d`.
5. **Verificar**: `infra/lab/verificar-ventana.sh <dominio>`. Comprueba:
   - contenedores `healthy`;
   - Caddy responde por HTTPS con certificado válido;
   - el Core rechaza una petición sin JWT (401) y, con `TOKEN=<access token>`, la acepta.
6. **Correr los jobs pendientes**:
   `docker compose --profile jobs run --rm jobs-recomendador python -m app.jobs.ajuste_preferencias`
   (y los demás de `services/*/app/jobs/`). Revisar su línea de corrida en los logs.
7. **Revisar el presupuesto** del lab en la página de AWS Academy.
8. **Al terminar: detener (Stop), no terminar (Terminate) la instancia.** Terminarla
   borra el disco y la IP elástica deja de estar asociada.
