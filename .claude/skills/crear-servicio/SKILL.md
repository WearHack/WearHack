---
name: crear-servicio
description: Anade un servicio nuevo a WearHack, Spring Boot o FastAPI, tocando los once sitios que lo mencionan y verificandolos con un comprobador. Usala cuando pidan crear, anadir o registrar un servicio nuevo, un modulo nuevo en services/, o una ruta nueva en el gateway. Olvidar un sitio no siempre falla: sin el filtro de CI el servicio deja de probarse y sin el de CD deja de desplegarse, en silencio.
---

# Crear un servicio

Un servicio nuevo se menciona en **once sitios**. Algunos fallan a gritos si se
olvidan: el test del gateway, o el build de CD con el contexto equivocado. Otros
**no fallan nunca**: sin el filtro de CI el servicio deja de probarse, y sin el
de CD deja de desplegarse, y nadie se entera hasta que algo revienta en
produccion. Por eso esta skill termina con un comprobador, no con una promesa.

No commitees ni cambies de rama: eso lo hace una persona (AGENTS.md, reglas 1 y
2). Al terminar, para y propon el mensaje con la skill `preparar-commit`.

## 0. Antes de tocar nada

**Confirma que hace falta un servicio nuevo.** Hoy son cuatro Java y dos Python,
y el equipo son seis personas que rotan: cada servicio mas es superficie
operativa. Si lo que se quiere es un endpoint, probablemente cabe en uno
existente. Un servicio nuevo es una decision de arquitectura y merece un ADR:
usa `nuevo-adr`.

**Nunca crees un servicio de clasificacion de prendas.** Esa capacidad corre en
el dispositivo (ADR 0002).

Pide o decide estos datos:

| Dato | Como |
|---|---|
| Nombre | minusculas, sin tildes ni guiones: `[a-z][a-z0-9]{1,30}` |
| Tipo | `java` (Spring Boot) o `python` (FastAPI) |
| Puerto | `python .claude/skills/crear-servicio/verificar-registro.py --siguiente-puerto` |
| Equipo dueno | `backend` para Java, `ia` para Python, salvo que digan otra cosa |
| Que hace | una frase, para las descripciones y las tablas |

## 1. Copiar el servicio de referencia

La referencia es **`closet`** para Java y **`colorimetria`** para Python. Los
servicios del mismo tipo son identicos a proposito: copia, no reinventes.

Copia la carpeta **sin** `target/`, `__pycache__/`, `.pytest_cache/` ni `.venv/`,
y sustituye en los archivos de texto:

- Java: `closet` por el nombre, `Closet` por el nombre con mayuscula inicial, y
  `8082` por el puerto. Renombra las tres clases (`...Application`,
  `...ApplicationTest`) y la carpeta del paquete `com/wearhack/<nombre>/`.
- Python: `colorimetria` por el nombre y `8085` por el puerto. Renombra
  `app/api/v1/colorimetria.py`. Borra `app/jobs/recalibrar_centroides.py`, que es
  especifico de colorimetria; deja `_runner.py` y `__init__.py`.

Despues **reescribe a mano** lo que la sustitucion no entiende: las descripciones
del `pom.xml` o `pyproject.toml`, los docstrings del endpoint stub y del
controlador, que hablan del dominio del servicio original. Un `closet` que dice
"colorimetria" en un comentario es un error esperando a un lector confundido.

El endpoint stub devuelve **501**, no datos inventados. Un stub que respondiera
algo invitaria a montar el cliente encima de datos falsos.

## 2. Los once sitios

Sustituye `<n>` por el nombre y `<N>` por el nombre en mayusculas.

| # | Archivo | Que anadir |
|---|---|---|
| 1 | `services/<n>/` | El modulo, con su `Dockerfile` |
| 2 | `services/pom.xml` | `<module><n></module>`. **Solo Java** |
| 3 | `docker-compose.yml` | El bloque del servicio, copiado del de referencia |
| 4 | `docker-compose.yml` | En `gateway.depends_on`: `<n>:` con `condition: service_healthy` |
| 5 | `.env.example` | `<N>_PORT=<puerto>` |
| 6 | `gateway/src/main/resources/application.yml` | La ruta: `id`, `uri` con `${URI_<N>:http://<n>:<puerto>}` y `Path=/api/v1/<n>/**` |
| 7 | `gateway/src/test/.../GatewayApplicationTest.java` | El nombre en la lista de `containsExactlyInAnyOrder`, y el nombre del metodo que cuenta las rutas |
| 8 | `.github/workflows/ci.yml` | Un filtro con `services/<n>/**`, bajo el paso `java` o el `python` segun el tipo |
| 9 | `.github/workflows/cd.yml` | El mismo filtro en el job `cambios` |
| 10 | `.github/workflows/cd.yml` | La opcion `- <n>` del despliegue manual y, **solo Python**, el nombre en la linea `colorimetria\|recomendador)` del `case` |
| 11 | Documentacion | `CODEOWNERS`, checklist de `pull_request_template.md`, fila del `README.md`, y las tablas de puertos de `AGENTS.md` y `docs/arquitectura.md` |

En los filtros de un servicio Java, copia exactamente las lineas de los demas:
en `ci.yml` van `services/<n>/**`, `services/pom.xml` y el propio `ci.yml`; en
`cd.yml` van `services/<n>/**` y `services/pom.xml`. Un cambio del POM padre
puede romper el servicio sin tocar su carpeta. Los Python llevan solo su carpeta
en CD, y su carpeta mas `ci.yml` en CI.

**Por que el sitio 10 tiene dos partes.** El `case` decide con que contexto se
construye la imagen. Los servicios Python se bastan solos en su carpeta; los Java
necesitan ver el POM padre. Un Python fuera de esa linea se construye con el
contexto de Java y **el despliegue falla, tarde**.

Si el servicio participa en el flujo de datos, actualiza tambien los diagramas de
`docs/arquitectura.md`.

## 3. Verificar

Primero el comprobador. Debe terminar con codigo 0:

```bash
python .claude/skills/crear-servicio/verificar-registro.py <n>
```

Cada linea `FALTA` dice que sitio y por que importa. **No lo des por bueno con
una sola linea en rojo**, y no lo silencies: si el comprobador y el repo
discrepan, uno de los dos esta mal y hay que saber cual.

Luego que compile y arranque, segun el tipo.

Java:

```bash
mvn -B -f services/<n>/pom.xml verify
```

Python:

```bash
cd services/<n> && uv venv && uv pip install -r pyproject.toml --extra dev && uv run pytest -q
```

El compose y el gateway:

```bash
docker compose config --quiet
```

```bash
mvn -B -f gateway/pom.xml verify
```

Por ultimo, levanta el entorno y comprueba de extremo a extremo con la skill
`verificar-entorno`: el servicio debe responder `/api/v1/<n>/health` **a traves
del gateway**, no solo en su puerto.

## 4. Cerrar

Resume que creaste y **propon** los commits con `preparar-commit`: el servicio
nuevo va en su propio commit `feat(<n>): ...`, y el registro en CI, compose y
gateway puede ir aparte. Recuerda que el scope nuevo `<n>` aparece por primera
vez en el historial.

No arregles de paso nada que veas en otros servicios: si hay algo que mejorar en
uno, se aplica a todos los del mismo tipo en su propia rama, o no se hace.
