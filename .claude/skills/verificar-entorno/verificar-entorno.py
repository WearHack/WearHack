"""Comprueba que el entorno local de WearHack esta sano de extremo a extremo.

Es el recorrido que se hizo a mano al montar el esqueleto, empaquetado:

  1. Docker responde
  2. todos los contenedores estan sanos
  3. cada servicio responde /api/v1/<servicio>/health A TRAVES DEL GATEWAY
  4. las trazas llegan al collector
  5. los buckets de MinIO existen
  6. MongoDB tiene sus colecciones y el indice compuesto de prendas

Solo lee. No levanta, no para y no borra nada: si el entorno no esta arriba, lo
dice y sale. Levantarlo es `docker compose up -d`.

La lista de servicios sale del propio docker-compose.yml, asi que un servicio
nuevo entra en la comprobacion sin tocar este archivo.

No lee `.env`, que tiene credenciales. Para hablar con Mongo usa las variables
que el contenedor ya trae puestas, sin que pasen por aqui.

Uso:

    python verificar-entorno.py                  comprueba lo que hay ahora
    python verificar-entorno.py --esperar 90     espera hasta 90 s a que todo este sano
"""

import argparse
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

RAIZ_COMPOSE = None  # se ejecuta desde la raiz del repo, donde vive docker-compose.yml

# Servicios que no se comprueban por el gateway. Los de infraestructura no exponen
# /api/v1/<nombre>/health. El Core tampoco: no va detras del gateway, se le pega
# directo (ver la seccion 3b). Mientras convivan el Core y los servicios viejos, esta
# lista cambia; cuando el gateway desaparezca, este script se reescribe.
INFRA = {"mongo", "minio", "minio-init", "otel-collector", "gateway", "core"}

# Modulos del Core. Cada uno responde /api/v1/<modulo>/health en el propio Core.
MODULOS_DEL_CORE = ("usuarios", "closet", "outfits", "publicidad")

# minio-init es un contenedor de un solo uso: termina y es lo esperado
UN_SOLO_USO = {"minio-init"}

COLECCIONES = {
    "usuarios", "prendas", "outfits", "selecciones",
    "correcciones_clasificacion", "configuracion", "catalogos",
}
INDICE_PRENDAS = "prendas_usuario_slot_clima"

resultados: list[tuple[str, bool, str]] = []


def anotar(comprobacion: str, ok: bool, detalle: str = "") -> bool:
    resultados.append((comprobacion, ok, detalle))
    marca = "ok   " if ok else "FALLA"
    print(f"  {marca}  {comprobacion}" + (f"  ->  {detalle}" if detalle else ""))
    return ok


def correr(*args: str, timeout: int = 60) -> subprocess.CompletedProcess:
    return subprocess.run(
        list(args), capture_output=True, text=True, encoding="utf-8",
        errors="replace", timeout=timeout,
    )


def compose(*args: str, timeout: int = 60) -> subprocess.CompletedProcess:
    return correr("docker", "compose", *args, timeout=timeout)


def estado_contenedores() -> dict[str, tuple[str, str]]:
    """servicio -> (estado, salud). La salud es '' si el contenedor no tiene healthcheck."""
    r = compose("ps", "--all", "--format", "json")
    estado = {}
    for linea in r.stdout.splitlines():
        linea = linea.strip()
        if not linea.startswith("{"):
            continue
        d = json.loads(linea)
        estado[d["Service"]] = (d.get("State", ""), d.get("Health", ""))
    return estado


def esta_sano(servicio: str, estado: tuple[str, str] | None) -> bool:
    if estado is None:
        return False
    corriendo, salud = estado
    if servicio in UN_SOLO_USO:
        return corriendo == "exited"
    if salud:
        return salud == "healthy"
    return corriendo == "running"


def puerto_publicado(servicio: str, puerto_interno: int) -> int | None:
    r = compose("port", servicio, str(puerto_interno))
    m = re.search(r":(\d+)\s*$", r.stdout.strip())
    return int(m.group(1)) if m else None


def puerto_del_gateway() -> int | None:
    return puerto_publicado("gateway", 8080)


def get_json(url: str) -> tuple[int, dict | None]:
    try:
        with urllib.request.urlopen(url, timeout=10) as r:
            return r.status, json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        return e.code, None
    except Exception:
        return 0, None


def main() -> int:
    # Repite texto que viene de docker (errores de Mongo, por ejemplo). En Windows,
    # con la salida por una tuberia, Python usa cp1252 y romperia con otros caracteres.
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument("--esperar", type=int, default=0, metavar="SEGUNDOS",
                    help="espera hasta este tiempo a que todo este sano antes de comprobar")
    args = ap.parse_args()

    print("Entorno local de WearHack\n")

    # 1. Docker
    try:
        r = correr("docker", "info", "--format", "{{.ServerVersion}}", timeout=30)
    except Exception as e:
        print(f"  FALLA  no se pudo ejecutar docker: {e}")
        return 1
    if r.returncode != 0 or not r.stdout.strip():
        anotar("Docker responde", False, "Docker Desktop no esta corriendo; arrancalo y reintenta")
        return 1
    anotar("Docker responde", True, f"version {r.stdout.strip()}")

    # 2. Contenedores
    servicios = compose("config", "--services")
    if servicios.returncode != 0:
        anotar("docker-compose.yml valido", False,
               "ejecutalo desde la raiz del repo; docker compose config no pudo leerlo")
        return 1
    esperados = [s for s in servicios.stdout.split() if s]

    limite = time.monotonic() + args.esperar
    while True:
        estado = estado_contenedores()
        if all(esta_sano(s, estado.get(s)) for s in esperados) or time.monotonic() >= limite:
            break
        time.sleep(3)

    for s in esperados:
        e = estado.get(s)
        if e is None:
            anotar(f"contenedor {s}", False, "no existe: falta 'docker compose up -d'")
        elif esta_sano(s, e):
            anotar(f"contenedor {s}", True, "termino bien" if s in UN_SOLO_USO else (e[1] or e[0]))
        else:
            if e[0] != "running":
                detalle = f"{e[0]}: esta parado; 'docker compose start {s}' o 'docker compose up -d'"
            else:
                detalle = f"running / {e[1] or 'sin healthcheck'}"
                if e[1] == "starting":
                    detalle += "; si acaba de arrancar, usa --esperar 90"
            anotar(f"contenedor {s}", False, detalle)

    # 3. Servicios por el gateway
    puerto = puerto_del_gateway()
    if puerto is None:
        anotar("gateway publicado", False, "no hay puerto publicado para el gateway")
    else:
        base = f"http://localhost:{puerto}"
        codigo, cuerpo = get_json(f"{base}/health")
        anotar("gateway /health", codigo == 200 and (cuerpo or {}).get("servicio") == "gateway",
               "" if codigo == 200 else f"HTTP {codigo}")
        for s in (x for x in esperados if x not in INFRA):
            codigo, cuerpo = get_json(f"{base}/api/v1/{s}/health")
            ok = codigo == 200 and (cuerpo or {}).get("servicio") == s and (cuerpo or {}).get("estado") == "UP"
            detalle = "" if ok else (f"HTTP {codigo}" if codigo != 200 else f"respondio {cuerpo}")
            anotar(f"{s} por el gateway", ok, detalle)

    # 3b. El Core, directo: no va detras del gateway.
    if "core" in esperados:
        puerto_core = puerto_publicado("core", 8090)
        if puerto_core is None:
            anotar("core publicado", False, "no hay puerto publicado para el core")
        else:
            base_core = f"http://localhost:{puerto_core}"
            codigo, cuerpo = get_json(f"{base_core}/health")
            anotar("core /health", codigo == 200 and (cuerpo or {}).get("servicio") == "core",
                   "" if codigo == 200 else f"HTTP {codigo}")
            for modulo in MODULOS_DEL_CORE:
                codigo, cuerpo = get_json(f"{base_core}/api/v1/{modulo}/health")
                ok = codigo == 200 and (cuerpo or {}).get("modulo") == modulo
                anotar(f"core, modulo {modulo}", ok,
                       "" if ok else (f"HTTP {codigo}" if codigo != 200 else f"respondio {cuerpo}"))

    # 4. Trazas. El collector agrupa en lotes de unos 5 s, asi que hay que dar tiempo.
    time.sleep(8)
    logs = compose("logs", "otel-collector", "--since", "45s").stdout
    lotes = [int(m.group(1)) for m in
             re.finditer(r'"data_type":\s*"traces".*?"spans":\s*(\d+)', logs)]
    anotar("trazas en el collector", bool(lotes) and sum(lotes) > 0,
           f"{sum(lotes)} spans en los ultimos 45 s" if lotes else "ningun span recibido en 45 s")

    # 5. Buckets. Los nombres los resuelve compose, sin leer .env desde aqui.
    buckets: list[str] = []
    cfg = compose("config", "--format", "json")
    if cfg.returncode == 0:
        try:
            env = json.loads(cfg.stdout)["services"]["minio-init"]["environment"]
            buckets = [env[k] for k in ("S3_BUCKET_PRENDAS", "S3_BUCKET_ROSTROS") if k in env]
        except (KeyError, ValueError):
            pass
    log_minio = compose("logs", "minio-init").stdout
    if not buckets:
        anotar("buckets de MinIO", False, "no se pudieron resolver los nombres desde el compose")
    else:
        for b in buckets:
            anotar(f"bucket {b}", b in log_minio and "Buckets listos" in log_minio,
                   "" if b in log_minio else "minio-init no lo menciona")

    # 6. Mongo. Las credenciales son las del propio contenedor: no pasan por aqui.
    js = ("const b=db.getSiblingDB(process.env.MONGO_DB);"
          "print(JSON.stringify({c:b.getCollectionNames().sort(),"
          "i:b.prendas.getIndexes().map(x=>x.name)}))")
    sh = ('mongosh --quiet -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" '
          f"--authenticationDatabase admin --eval '{js}'")
    m = compose("exec", "-T", "mongo", "sh", "-c", sh, timeout=60)
    datos = None
    for linea in reversed(m.stdout.splitlines()):
        if linea.strip().startswith("{"):
            try:
                datos = json.loads(linea)
            except ValueError:
                pass
            break
    if datos is None:
        anotar("colecciones de Mongo", False, "no se pudo consultar Mongo: " + (m.stderr.strip()[:120] or "sin salida"))
    else:
        faltan = COLECCIONES - set(datos["c"])
        anotar("colecciones de Mongo", not faltan,
               f"{len(COLECCIONES) - len(faltan)}/{len(COLECCIONES)}" + (f"; faltan {sorted(faltan)}" if faltan else ""))
        anotar("indice compuesto de prendas", INDICE_PRENDAS in datos["i"],
               "" if INDICE_PRENDAS in datos["i"] else f"falta {INDICE_PRENDAS}")

    fallas = [r for r in resultados if not r[1]]
    print()
    if fallas:
        print(f"{len(fallas)} de {len(resultados)} comprobaciones fallan.")
        return 1
    print(f"Las {len(resultados)} comprobaciones pasan.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
