# AGENTS.md

Instrucciones para cualquier agente que trabaje en este repositorio. Es el
archivo canonico: `CLAUDE.md` solo lo importa.

Si algo de aqui choca con lo que te pide una persona, **gana la persona**, pero
dilo en voz alta antes de hacerlo.

---

## Que es WearHack

Un "AI Closet Assistant" B2C. El usuario digitaliza su closet, la IA calcula su
colorimetria y genera outfits semanales. La monetizacion viene de recomendar
**prendas puente** del catalogo de marcas aliadas: piezas que, combinadas con lo
que el usuario ya tiene, desbloquean varios outfits nuevos.

Monorepo con un cliente Flutter, un API gateway, cuatro servicios Spring Boot,
dos servicios FastAPI e infraestructura.

**Estado: esqueleto.** Todo arranca, responde `/health` y emite trazas. No hay
logica de negocio, modelos de IA ni UI real. Si encuentras un stub, no es un
descuido: es el estado esperado.

---

## Tres reglas que no se negocian

### 1. No commitees ni hagas push

Los commits los hace una persona. No ejecutes `git commit`, `git push`, ni crees
ramas por tu cuenta.

Cuando termines un cambio, para, resume que tocaste, y **propon el mensaje de
commit** siguiendo la convencion de mas abajo. La skill `preparar-commit` hace
exactamente eso.

### 2. No trabajes sobre `main` ni sobre `develop`

`main` es produccion y `develop` es integracion. Si estas en una de las dos, di
en que rama deberia ir el cambio y espera. No cambies de rama tu.

### 3. No crees un servicio backend de clasificacion de prendas

Esto no es un hueco pendiente. Es una decision de arquitectura
([ADR 0002](docs/adr/0002-clasificacion-de-prendas-on-device.md)): quitar el
fondo y deducir tipo, textura y patron corre **en el telefono**, con
LiteRT/TFLite.

Si alguien pide "un endpoint para clasificar prendas", lo correcto es decir que
esa capacidad vive en `client/lib/platform/captura/` y preguntar que problema
real hay detras.

---

## Lo que el dominio impone

**La foto original nunca sale del dispositivo.** Solo sube la imagen ya procesada
junto con los atributos.

**Para la colorimetria solo viaja el recorte facial.** El dispositivo detecta el
rostro, lo recorta y lo normaliza, y sube solo eso. No anadas un camino que
mande la foto completa, ni siquiera como plan B si el recorte falla. Ver
[ADR 0016](docs/adr/0016-solo-el-recorte-facial-sale-del-dispositivo.md).

**Los cuatro servicios Java son identicos a proposito.** `usuarios`, `closet`,
`outfits` y `publicidad` solo difieren en nombre, puerto y ruta base. El equipo
son seis generalistas que rotan: conocer uno es conocer los cuatro. Si mejoras
uno, aplica lo mismo a los otros tres o no lo hagas.

**Los dos servicios Python tambien.** `health.py`, `telemetry.py`,
`logging_config.py` y `jobs/_runner.py` son copias literales. La duplicacion es
deliberada: una libreria compartida romperia los path filters de CI
([ADR 0006](docs/adr/0006-servicios-de-ia-en-fastapi.md)).

**En web no hay captura.** El codigo de camara e interpretes vive detras de un
import condicional en `client/lib/platform/captura.dart`. La rama movil depende
de `dart:io`, que en web no existe, asi que un import mal colocado rompe
`flutter build web` y en ningun otro sitio.

---

## Convenciones

### Commits

[Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/).

```
<tipo>(<scope>): <descripcion en minuscula>
```

| | |
|---|---|
| **Tipos** | `feat`, `fix`, `chore`, `ci`, `docs`, `build`, `refactor`, `test`, `perf` |
| **Scopes** | `repo`, `gateway`, `usuarios`, `closet`, `outfits`, `publicidad`, `colorimetria`, `recomendador`, `client`, `infra`, `ci`, `docs`, `agents` |

El cuerpo explica **por que**, no que. El que ya esta en el diff.

Sin tildes ni enes en los mensajes, que es lo que hace el historial actual.

### Ramas

```
<tipo>/<scope>-<descripcion-corta>
```

Mismos tipos y scopes. Minusculas, guiones, por debajo de unos 50 caracteres.
Ejemplos: `feat/gateway-autenticacion-jwt`, `fix/closet-503-servicio-caido`.

El scope importa mas aqui que en otros repos: con los path filters de CI, te dice
de antemano que se va a construir y, por `CODEOWNERS`, quien va a revisar.

---

## Comandos

Estos estan verificados. Si alguno falla, es una senal, no una molestia.

Levantar el entorno:

```bash
cp .env.example .env && docker compose up -d
```

Comprobar los seis servicios por el gateway:

```bash
for s in usuarios closet outfits publicidad colorimetria recomendador; do curl -sf "localhost:8080/api/v1/$s/health" && echo; done
```

Construir y probar los cuatro servicios Java:

```bash
mvn -B -f services/pom.xml verify
```

Probar un servicio Python (necesita `uv`, se instala con `pip install uv`):

```bash
cd services/colorimetria && uv venv && uv pip install -r pyproject.toml --extra dev && uv run pytest -q
```

El cliente:

```bash
cd client && dart format lib test && flutter analyze && flutter test
```

**Ojo con `flutter build apk` en Windows.** Puede fallar con
`Unable to establish loopback connection`. No es el SDK: la JVM no puede crear
sockets de dominio Unix en el directorio temporal por defecto. Se arregla con
`JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=C:\temp-java-sockets`, con esa
carpeta creada.

### Puertos

| Servicio | Puerto |
|---|---|
| gateway | 8080 |
| usuarios | 8081 |
| closet | 8082 |
| outfits | 8083 |
| publicidad | 8084 |
| colorimetria | 8085 |
| recomendador | 8086 |
| MongoDB | 27017 |
| MinIO | 9000, consola 9001 |
| OpenTelemetry Collector | 4317 gRPC, 4318 HTTP |

---

## Donde no tocar

**`client/android/`, `client/ios/` y `client/web/`** los genera `flutter
create`. Un cambio a mano se pierde en la siguiente regeneracion. Si hace falta
tocarlos, dilo y que quede anotado.

**`docker compose down -v` borra los volumenes.** Se lleva por delante los datos
de Mongo y los buckets de MinIO. Usa `down` a secas salvo que alguien pida
explicitamente empezar de cero.

**`.env`** tiene credenciales locales. No lo leas ni lo imprimas.

---

## Anadir un servicio toca seis sitios

Esta es la trampa mas facil del repo. Un servicio nuevo necesita:

1. Su modulo, con POM y `Dockerfile`
2. Registro en `services/pom.xml` (si es Java)
3. Entrada en `docker-compose.yml`
4. Filtro en `.github/workflows/ci.yml`
5. Linea en `.github/CODEOWNERS`
6. Ruta en `gateway/src/main/resources/application.yml`

**Olvidar el cuarto no rompe nada**, y por eso es el peligroso: el servicio
simplemente deja de construirse en CI y nadie se entera hasta que algo falla en
produccion.

Usa la skill `crear-servicio`, que los cubre los seis.

---

## Huecos conocidos

No son descuidos. Si vas a "arreglarlos", que sea a proposito y en su propia
rama.

- **La autenticacion del gateway es un stub** que deja pasar todo y avisa en cada
  arranque. No desplegar fuera de local hasta implementarla.
- **Un servicio caido devuelve 500 por el gateway**, y deberia ser 503. Arreglarlo
  bien pide un circuit breaker.
- **`infra/terraform/` esta vacio.** Lo que haya en AWS no esta en codigo.
- **Las dependencias transitivas de Python no estan fijadas.** Ver
  [ADR 0017](docs/adr/0017-dependencias-de-python-sin-lock.md).

---

## Donde mirar

| Para | Ve a |
|---|---|
| Como levantar todo | [README.md](README.md) |
| Como encaja el sistema | [docs/arquitectura.md](docs/arquitectura.md) |
| Por que algo es como es | [docs/adr/](docs/adr/) |
| El cliente en detalle | [client/README.md](client/README.md) |

Antes de proponer un cambio de arquitectura, mira si ya hay un ADR que lo
decidio. Si lo hay y sigues pensando que conviene cambiarlo, escribe uno nuevo
que sustituya al anterior en vez de contradecirlo en silencio.
