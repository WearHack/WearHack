---
name: verificar-entorno
description: Comprueba que el entorno local de WearHack esta sano de extremo a extremo. Contenedores, cada servicio a traves del gateway, trazas en el collector, buckets de MinIO y colecciones de Mongo. Usala despues de levantar el compose, de tocar un servicio, el gateway o el compose, o cuando algo "no responde" y no se sabe por donde empezar. Solo lee, no levanta ni borra nada.
---

# Verificar el entorno local

Es el recorrido que se hizo a mano al montar el esqueleto, empaquetado. Sirve para
tener una respuesta concreta a "esta todo bien?" en vez de mirar `docker compose
ps` y suponer.

**Solo lee.** No levanta, no para y no borra nada. Si el entorno no esta arriba,
lo dice y termina. Levantarlo es una decision aparte y pide confirmacion.

## Uso

Desde la raiz del repo:

```bash
python .claude/skills/verificar-entorno/verificar-entorno.py
```

Si acabas de levantarlo, dale tiempo: los servicios Java tardan unos 40 segundos
en quedar sanos.

```bash
python .claude/skills/verificar-entorno/verificar-entorno.py --esperar 90
```

Termina con codigo 0 si todo pasa y 1 si algo falla. Cada linea `FALLA` dice que
y, cuando se puede, que hacer.

## Que comprueba

| | Comprobacion |
|---|---|
| 1 | Docker responde |
| 2 | Cada contenedor esta sano. `minio-init` es de un solo uso: lo correcto es que haya terminado |
| 3 | Cada servicio responde `/api/v1/<servicio>/health` **a traves del gateway**, no solo en su puerto |
| 4 | Llegan trazas al collector de OpenTelemetry |
| 5 | Existen los buckets `prendas` y `rostros` de MinIO |
| 6 | Mongo tiene las siete colecciones y el indice `prendas_usuario_slot_clima` |

La lista de servicios sale del propio `docker-compose.yml`. Un servicio nuevo entra
en la comprobacion sin tocar el script.

## Como leer un fallo

- **Un contenedor parado o no sano y su linea "por el gateway" fallan a la vez:**
  el problema es ese servicio. Mira `docker compose logs <servicio>`.
- **Solo falla "por el gateway" y el contenedor esta sano:** puede ser el gateway
  con una IP vieja en cache tras recrear el servicio. Ocurrio una vez al montar el
  esqueleto, se arreglo con `docker compose restart gateway` y no se llego a
  confirmar la causa. Prueba eso primero, y si se repite, investiga en vez de
  reiniciar cada vez.
- **Un servicio caido da HTTP 500 por el gateway**, no 503. Es un hueco conocido
  (ver AGENTS.md), no una pista de que el gateway este roto.
- **Fallan las trazas pero todo lo demas pasa:** el collector recibe en lotes de
  unos 5 segundos y el script espera 8. Si el entorno acaba de arrancar, repite.
- **Fallan las colecciones de Mongo:** el script de init solo corre con el volumen
  vacio. Si la base ya existia sin ellas, hay que relanzarlo a mano. No borres el
  volumen para arreglarlo sin que alguien lo pida: se pierden los datos.

## Lo que no hace

- No lee `.env`: tiene credenciales. Para hablar con Mongo usa las variables que el
  contenedor ya trae, sin que pasen por el script.
- No valida el contenido de las trazas, solo que llegan. Que el `trace_id` se
  propague entre gateway y servicios se comprobo a mano al montar el esqueleto y
  no esta automatizado.
- No comprueba autenticacion: el filtro del gateway es un stub que deja pasar todo.
