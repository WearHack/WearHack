"""Comprueba que un servicio esta registrado en todos los sitios que lo mencionan.

Anadir un servicio toca once sitios. Olvidar algunos falla a gritos: el test del
gateway, o el build de CD con el contexto equivocado. Olvidar otros no falla
nunca: si falta el filtro de CI el servicio deja de probarse, y si falta el de
CD deja de desplegarse, sin un solo error. Este script existe para los segundos.

Uso:

    python verificar-registro.py <servicio>          comprueba los once sitios
    python verificar-registro.py --siguiente-puerto  imprime el primer puerto libre

Sale con codigo 0 si todo cuadra y 1 si falta algo. Solo lee, nunca escribe.
"""

import argparse
import pathlib
import re
import sys

# .claude/skills/crear-servicio/<este archivo> -> la raiz del repo esta 3 niveles arriba
RAIZ_POR_DEFECTO = pathlib.Path(__file__).resolve().parents[3]


def leer(raiz: pathlib.Path, ruta: str) -> str | None:
    archivo = raiz / ruta
    if not archivo.is_file():
        return None
    return archivo.read_text(encoding="utf-8")


def bloque_del_gateway(compose: str) -> str:
    """El texto del servicio 'gateway' en el compose, hasta el siguiente servicio."""
    m = re.search(r"(?ms)^  gateway:\n(.*?)(?=^  \S)", compose)
    return m.group(1) if m else ""


def puertos_de_servicios(env_example: str) -> dict[str, int]:
    """Los puertos 8080..8999 de .env.example. Excluye Mongo, el S3 local y el collector."""
    puertos = {}
    for m in re.finditer(r"(?m)^([A-Z]+)_PORT=(\d+)\s*$", env_example):
        puerto = int(m.group(2))
        if 8080 <= puerto <= 8999:
            puertos[m.group(1)] = puerto
    return puertos


def comprobar(raiz: pathlib.Path, nombre: str) -> list[tuple[str, bool, str]]:
    n = re.escape(nombre)
    resultados: list[tuple[str, bool, str]] = []

    def anotar(sitio: str, ok: bool, detalle: str = "") -> None:
        resultados.append((sitio, ok, detalle))

    def con_texto(sitio: str, ruta: str, patron: str, hint: str) -> None:
        texto = leer(raiz, ruta)
        if texto is None:
            anotar(sitio, False, f"no existe {ruta}")
        elif re.search(patron, texto):
            anotar(sitio, True)
        else:
            anotar(sitio, False, hint)

    servicio = raiz / "services" / nombre
    es_java = (servicio / "pom.xml").is_file()
    es_python = (servicio / "pyproject.toml").is_file()

    # 1. El modulo
    if not servicio.is_dir():
        anotar("1. modulo", False, f"no existe services/{nombre}/")
        return resultados
    if es_java == es_python:
        anotar("1. modulo", False, "debe tener pom.xml (Java) o pyproject.toml (Python), uno solo")
        return resultados
    anotar("1. modulo", (servicio / "Dockerfile").is_file(),
           "" if (servicio / "Dockerfile").is_file() else f"falta services/{nombre}/Dockerfile")
    tipo = "java" if es_java else "python"

    # 2. POM agregador (solo Java)
    if es_java:
        con_texto("2. services/pom.xml", "services/pom.xml",
                  rf"<module>{n}</module>", f"falta <module>{nombre}</module>")

    # 3 y 4. docker-compose
    compose = leer(raiz, "docker-compose.yml") or ""
    anotar("3. docker-compose: servicio", bool(re.search(rf"(?m)^  {n}:\s*$", compose)),
           f"falta el servicio '{nombre}:'")
    gw = bloque_del_gateway(compose)
    anotar("4. docker-compose: depends_on del gateway",
           bool(re.search(rf"(?m)^      {n}:\n\s+condition: service_healthy", gw)),
           "el gateway no espera a este servicio: puede arrancar antes y rutear a nada")

    # 5. .env.example
    puerto_var = f"{nombre.upper()}_PORT"
    con_texto("5. .env.example", ".env.example", rf"(?m)^{puerto_var}=\d+\s*$",
              f"falta {puerto_var}=<puerto>")

    # 6. Ruta del gateway
    gw_yml = leer(raiz, "gateway/src/main/resources/application.yml") or ""
    anotar("6. gateway: ruta",
           bool(re.search(rf"id: {n}\b", gw_yml)) and f"Path=/api/v1/{nombre}/**" in gw_yml,
           f"falta la ruta 'id: {nombre}' con Path=/api/v1/{nombre}/**")

    # 7. Test del gateway
    con_texto("7. gateway: test de rutas",
              "gateway/src/test/java/com/wearhack/gateway/GatewayApplicationTest.java",
              rf'"{n}"',
              f'falta "{nombre}" en la lista de rutas del test: CI fallara en el gateway')

    # 8 y 9. Filtros de CI y CD
    filtro = rf"(?m)^\s+{n}:\n\s+- 'services/{n}/\*\*'"
    con_texto("8. ci.yml: filtro", ".github/workflows/ci.yml", filtro,
              "SIN FILTRO EL SERVICIO NUNCA SE PRUEBA EN CI y nada falla por ello")
    con_texto("9. cd.yml: filtro", ".github/workflows/cd.yml", filtro,
              "SIN FILTRO EL SERVICIO NUNCA SE DESPLIEGA y nada falla por ello")

    # 10. cd.yml: opcion del despliegue manual y contexto de build
    cd = leer(raiz, ".github/workflows/cd.yml") or ""
    anotar("10a. cd.yml: opcion del dispatch",
           bool(re.search(rf"(?m)^\s+- {n}\s*$", cd)),
           "no se puede desplegar a mano desde la interfaz de Actions")
    linea_python = re.search(r"(?m)^\s+((?:[a-z]+\|)+[a-z]+)\)\s*$", cd)
    en_python = bool(linea_python) and nombre in linea_python.group(1).split("|")
    if es_python:
        anotar("10b. cd.yml: contexto de build (Python)", en_python,
               "un servicio Python sin esta linea se construye con el contexto de Java y el despliegue falla")
    else:
        anotar("10b. cd.yml: contexto de build (Java)", not en_python,
               "un servicio Java NO va en la linea de Python del case")

    # 11. Propiedad y documentacion
    con_texto("11a. CODEOWNERS", ".github/CODEOWNERS", rf"(?m)^/services/{n}/\s+@",
              f"falta la linea /services/{nombre}/ con su equipo")
    con_texto("11b. plantilla de PR", ".github/pull_request_template.md", rf"- \[ \] {n}\b",
              f"falta '- [ ] {nombre}' en el checklist")
    con_texto("11c. README", "README.md", rf"services/{n}/", f"falta la fila de services/{nombre}/")
    fila_puerto = rf"(?m)^\| {n} \| \d+ \|"
    con_texto("11d. AGENTS.md: tabla de puertos", "AGENTS.md", fila_puerto, f"falta '| {nombre} | <puerto> |'")
    con_texto("11e. arquitectura.md: tabla de puertos", "docs/arquitectura.md", fila_puerto,
              f"falta '| {nombre} | <puerto> |'")

    # Coherencia: el puerto no se repite y coincide entre .env.example y el compose
    env = leer(raiz, ".env.example") or ""
    puertos = puertos_de_servicios(env)
    puerto = puertos.get(nombre.upper())
    if puerto is not None:
        repetidos = [k for k, v in puertos.items() if v == puerto and k != nombre.upper()]
        anotar("puerto unico", not repetidos,
               f"el puerto {puerto} tambien lo usa {', '.join(repetidos)}" if repetidos else "")
        anotar("puerto coherente con el compose",
               f"SERVER_PORT: {puerto}" in compose,
               f"SERVER_PORT en el compose no es {puerto}, el de .env.example")

    resultados.insert(0, ("tipo detectado", True, tipo))
    return resultados


def siguiente_puerto(raiz: pathlib.Path) -> int:
    puertos = puertos_de_servicios(leer(raiz, ".env.example") or "")
    return (max(puertos.values()) + 1) if puertos else 8081


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument("servicio", nargs="?", help="nombre del servicio, en minusculas y sin tildes")
    ap.add_argument("--siguiente-puerto", action="store_true")
    ap.add_argument("--raiz", type=pathlib.Path, default=RAIZ_POR_DEFECTO, help=argparse.SUPPRESS)
    args = ap.parse_args()

    if args.siguiente_puerto:
        print(siguiente_puerto(args.raiz))
        return 0

    if not args.servicio:
        ap.error("indica el servicio, o usa --siguiente-puerto")

    if not re.fullmatch(r"[a-z][a-z0-9]{1,30}", args.servicio):
        print("El nombre debe ir en minusculas, sin tildes ni guiones: [a-z][a-z0-9]{1,30}")
        return 2

    resultados = comprobar(args.raiz, args.servicio)
    falta = 0
    for sitio, ok, detalle in resultados:
        marca = "ok  " if ok else "FALTA"
        linea = f"  {marca}  {sitio}"
        if detalle:
            linea += f"  ->  {detalle}"
        print(linea)
        if not ok:
            falta += 1

    total = len([r for r in resultados if r[0] != "tipo detectado"])
    print()
    if falta:
        print(f"{falta} de {total} comprobaciones fallan para '{args.servicio}'.")
        return 1
    print(f"'{args.servicio}' pasa las {total} comprobaciones de registro.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
