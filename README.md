# WearHack

AI Closet Assistant. El usuario digitaliza su closet, la IA calcula su
colorimetria y genera outfits semanales. La monetizacion viene de recomendar
**prendas puente** del catalogo de marcas aliadas: piezas que, combinadas con lo
que el usuario ya tiene, desbloquean varios outfits nuevos.

Monorepo con el cliente Flutter, un API gateway, cuatro servicios Spring Boot,
dos servicios FastAPI e infraestructura.

> **Estado: esqueleto.** Todo arranca, responde `/health` y emite trazas. No hay
> logica de negocio, modelos de IA ni UI real.

## Levantar el entorno local

Tres comandos. Arranque en frio desde cero: unos 50 segundos.

```bash
cp .env.example .env
```

```bash
docker compose up -d
```

```bash
curl -s localhost:8080/api/v1/usuarios/health
```

Eso levanta los siete servicios, MongoDB con sus colecciones e indices, el S3 local
(S3Mock) con sus buckets y el collector de OpenTelemetry.

Para comprobar los seis servicios de una vez:

```bash
for s in usuarios closet outfits publicidad colorimetria recomendador; do curl -sf "localhost:8080/api/v1/$s/health" && echo; done
```

Y para ver que las trazas llegan:

```bash
docker compose logs otel-collector | grep spans | tail -3
```

## Levantar el cliente

```bash
cd client && flutter run --dart-define=API_BASE=http://10.0.2.2:8080
```

`10.0.2.2` es como el emulador de Android ve el equipo anfitrion. En un
dispositivo fisico hay que poner la IP de la maquina en la red local. Mas
detalles en [client/README.md](client/README.md).

## Lo que conviene entender antes de tocar nada

**La clasificacion de prendas no pasa por el backend.** Quitar el fondo y deducir
tipo, textura y patron corre en el telefono con LiteRT/TFLite. No existe ni va a
existir un servicio de clasificacion, y la foto original nunca se sube. Ver
[ADR 0002](docs/adr/0002-clasificacion-de-prendas-on-device.md).

**Para la colorimetria solo viaja el recorte facial.** El dispositivo detecta el
rostro, lo recorta y lo normaliza, y sube solo eso. Ver
[ADR 0016](docs/adr/0016-solo-el-recorte-facial-sale-del-dispositivo.md).

**En web no hay captura.** Ahi WearHack es solo consulta y gestion. El codigo de
captura esta aislado tras un import condicional, y un import mal colocado rompe
`flutter build web` y en ningun otro sitio.

## Estructura

| Ruta | Que es |
|---|---|
| `client/` | Cliente Flutter. Android, iOS y Web desde un solo proyecto |
| `gateway/` | Spring Cloud Gateway. Ruteo, autenticacion y control de acceso |
| `services/usuarios/` | Perfiles y cuentas |
| `services/closet/` | Prendas digitalizadas |
| `services/outfits/` | Outfits semanales y selecciones |
| `services/publicidad/` | Catalogo de marcas aliadas |
| `services/colorimetria/` | Temporada de color por nearest-centroid |
| `services/recomendador/` | Motor combinatorio de outfits |
| `infra/local/` | Init de Mongo y config del collector |
| `infra/terraform/` | Infraestructura de AWS. Pendiente |
| `docs/` | Arquitectura y decisiones |

## Documentacion

- [Arquitectura](docs/arquitectura.md), con diagramas Mermaid as-code
- [Decisiones de arquitectura](docs/adr/), un ADR por decision tomada

## Trabajar en un servicio

Los cuatro servicios Java son identicos salvo nombre, puerto y ruta base. Los dos
de Python tambien. Es deliberado: el equipo rota, y conocer uno es conocer todos.

```bash
mvn -f services/pom.xml verify
```

Los servicios de Python usan [uv](https://docs.astral.sh/uv/). Si no lo tienes:

```bash
pip install uv
```

```bash
cd services/colorimetria && uv venv && uv pip install -r pyproject.toml --extra dev && uv run pytest -q
```

```bash
cd client && flutter analyze && flutter test
```

Los jobs nocturnos corren con la misma imagen de su servicio:

```bash
docker compose run --rm recomendador python -m app.jobs.ajuste_preferencias
```

## CI

Cada PR construye **solo lo que cambio**. Un cambio en `closet` lanza un job, no
ocho. El check obligatorio en la proteccion de rama debe ser `ci`, el job resumen,
y no los jobs individuales: marcar esos bloquearia la fusion cada vez que uno se
salta. Ver [ADR 0014](docs/adr/0014-ci-con-path-filters-por-servicio.md).

## Huecos conocidos

- `infra/terraform/` esta vacio. Lo que haya en AWS todavia no esta en codigo.
- La autenticacion del gateway es un stub que deja pasar todo, y avisa en cada
  arranque. No desplegar fuera de local hasta implementarla.
- Un servicio caido devuelve 500 por el gateway, y deberia ser 503.
- Las dependencias transitivas de Python no estan fijadas. Ver
  [ADR 0017](docs/adr/0017-dependencias-de-python-sin-lock.md).
