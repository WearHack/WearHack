"""Prepara un commit sin hacerlo: agrupa cambios por scope y valida el mensaje.

En WearHack los commits los hace una persona, no el agente. Este script ayuda a
que lo que se le propone a esa persona este bien armado:

    python preparar-commit.py                     analiza el arbol de trabajo
    python preparar-commit.py --validar "msg"     valida un mensaje de commit
    python preparar-commit.py --archivo msg.txt   valida un mensaje guardado en un archivo

Solo lee. Ejecuta `git status` y `git branch --show-current`; nunca `git add` ni
`git commit`.
"""

import argparse
import pathlib
import re
import subprocess
import sys

RAIZ = pathlib.Path(__file__).resolve().parents[3]

TIPOS = ["feat", "fix", "chore", "ci", "docs", "build", "refactor", "test", "perf", "style", "revert"]
SCOPES_FIJOS = {"repo", "gateway", "client", "infra", "ci", "docs", "agents", "services"}

# Archivos que no deben entrar nunca a un commit. Si aparecen en `git status` es que
# .gitignore no los cubre, y eso ya es un problema.
NO_COMMITEAR = [
    (r"(^|/)\.env$", "credenciales locales"),
    (r"(^|/)target/", "artefactos de build de Maven"),
    (r"(^|/)__pycache__/", "cache de Python"),
    (r"\.py[co]$", "bytecode de Python"),
    (r"(^|/)\.dart_tool/", "cache de Dart"),
    (r"(^|/)build/", "artefactos de build"),
    (r"(^|/)local\.properties$", "ruta local del SDK de Android"),
    (r"\.iml$", "archivo de IDE"),
    (r"(^|/)\.idea/", "carpeta de IDE"),
    (r"(^|/)node_modules/", "dependencias de Node"),
    (r"(^|/)\.claude/settings\.local\.json$", "ajustes personales de agentes"),
    (r"\.(pem|key)$", "clave privada"),
    (r"\.tfstate", "estado de Terraform"),
]

SCOPES_DE_RAMA_QUE_NO_LO_SON = {"ai"}  # solo documenta el caso conocido; el aviso es generico


def git(*args: str, raiz: pathlib.Path) -> str:
    r = subprocess.run(["git", *args], cwd=raiz, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    return r.stdout


def scopes_validos(raiz: pathlib.Path) -> set[str]:
    servicios = {
        d.name for d in (raiz / "services").glob("*")
        if d.is_dir() and ((d / "pom.xml").is_file() or (d / "pyproject.toml").is_file())
    }
    return SCOPES_FIJOS | servicios


def scope_de(ruta: str, servicios: set[str]) -> str:
    p = ruta.replace("\\", "/")
    partes = p.split("/")
    if partes[0] == "services":
        return partes[1] if len(partes) > 2 and partes[1] in servicios else "services"
    if partes[0] in {"gateway", "client"}:
        return partes[0]
    if partes[0] == "infra" or p in {"docker-compose.yml", ".env.example"}:
        return "infra"
    if p.startswith(".github/workflows/"):
        return "ci"
    if partes[0] == "docs" or p == "README.md":
        return "docs"
    if partes[0] == ".claude" or p in {"AGENTS.md", "CLAUDE.md"}:
        return "agents"
    return "repo"


def tipo_probable(archivos: list[tuple[str, str]], scope: str) -> str:
    """Una pista, no una decision: quien escribe el mensaje sabe mas que este script."""
    if scope == "docs":
        return "docs"
    if scope == "ci":
        return "ci"
    todo_nuevo = all(estado in {"??", "A "} for estado, _ in archivos)
    if all(re.search(r"Dockerfile$|pom\.xml$|pyproject\.toml$|package\.json$", r) for _, r in archivos):
        return "build"
    # Una skill nueva es una capacidad nueva, no mantenimiento.
    if scope == "agents" and todo_nuevo and any(".claude/skills/" in r.replace("\\", "/") for _, r in archivos):
        return "feat"
    if scope in {"repo", "agents"}:
        return "chore"
    return "feat" if todo_nuevo else "fix o feat"


def leer_estado(raiz: pathlib.Path) -> list[tuple[str, str]]:
    salida = git("status", "--porcelain=v1", "-z", "-uall", raiz=raiz)
    entradas = [e for e in salida.split("\0") if e]
    cambios, i = [], 0
    while i < len(entradas):
        e = entradas[i]
        estado, ruta = e[:2], e[3:]
        if estado[0] in "RC":  # renombrado o copiado: la entrada siguiente es el origen
            i += 1
        cambios.append((estado, ruta))
        i += 1
    return cambios


def revisar_rama(rama: str, scopes: set[str]) -> None:
    if rama in {"main", "develop"}:
        print(f"  ERROR  Estas en '{rama}'. No se trabaja sobre ella (AGENTS.md, regla 2). "
              "Di en que rama deberia ir el cambio y espera.")
        return
    m = re.fullmatch(r"(feat|fix|chore|ci|docs|build|refactor|test|perf)/([a-z0-9]+(?:-[a-z0-9]+)*)", rama)
    if not m:
        print(f"  aviso  La rama '{rama}' no sigue <tipo>/<scope>-<descripcion>.")
        return
    primero = m.group(2).split("-")[0]
    if primero not in scopes:
        print(f"  aviso  '{primero}' no es un scope conocido. Los validos: {', '.join(sorted(scopes))}.")
    if len(rama) > 50:
        print(f"  aviso  La rama mide {len(rama)} caracteres; conviene que no pase de unos 50.")


def analizar(raiz: pathlib.Path) -> int:
    scopes = scopes_validos(raiz)
    rama = git("branch", "--show-current", raiz=raiz).strip() or "(sin rama: HEAD suelto)"
    print(f"Rama: {rama}")
    revisar_rama(rama, scopes)

    cambios = leer_estado(raiz)
    if not cambios:
        print("\nNo hay cambios que commitear.")
        return 0

    print()
    prohibidos = []
    for estado, ruta in cambios:
        for patron, motivo in NO_COMMITEAR:
            if re.search(patron, ruta.replace("\\", "/")):
                prohibidos.append((ruta, motivo))
                break
    if prohibidos:
        print("NO COMMITEAR (deberia estar en .gitignore):")
        for ruta, motivo in prohibidos:
            print(f"  ERROR  {ruta}  ->  {motivo}")
        print()
    excluidos = {r for r, _ in prohibidos}

    servicios = scopes - SCOPES_FIJOS
    grupos: dict[str, list[tuple[str, str]]] = {}
    for estado, ruta in cambios:
        if ruta in excluidos:
            continue
        grupos.setdefault(scope_de(ruta, servicios), []).append((estado, ruta))

    print(f"{len(cambios) - len(excluidos)} archivos en {len(grupos)} scope(s):\n")
    for scope in sorted(grupos):
        archivos = grupos[scope]
        print(f"[{scope}]  tipo probable: {tipo_probable(archivos, scope)}")
        for estado, ruta in archivos:
            print(f"   {estado}  {ruta}")
        print()

    if len(grupos) > 1:
        print("Hay mas de un scope: conviene UN COMMIT POR SCOPE. Uno solo mezclado se revisa")
        print("peor y no se puede revertir por partes. Los comandos, uno por commit:\n")
    else:
        print("Un solo scope. Comandos:\n")
    for scope in sorted(grupos):
        rutas = " ".join(f'"{r}"' for _, r in grupos[scope])
        print(f"  git add {rutas}")
    print("\nEscribe el mensaje y compruebalo con:  python preparar-commit.py --validar \"<mensaje>\"")
    return 1 if prohibidos or rama in {"main", "develop"} else 0


def validar(mensaje: str, raiz: pathlib.Path) -> int:
    errores: list[str] = []
    avisos: list[str] = []
    scopes = scopes_validos(raiz)

    lineas = mensaje.strip("\n").split("\n")
    cabecera = lineas[0] if lineas and lineas[0] else ""
    if not cabecera:
        print("  ERROR  el mensaje esta vacio")
        return 1

    m = re.fullmatch(rf"({'|'.join(TIPOS)})(?:\(([^)]*)\))?(!)?: (.+)", cabecera)
    if not m:
        errores.append(f"la cabecera no sigue '<tipo>(<scope>): <descripcion>'. Tipos: {', '.join(TIPOS)}")
    else:
        _, scope, _, descripcion = m.groups()
        if scope is None:
            avisos.append("sin scope. Vale para cosas transversales, como un ADR; en el resto, ponlo.")
        elif scope not in scopes:
            errores.append(f"el scope '{scope}' no existe. Validos: {', '.join(sorted(scopes))}")
        if descripcion.endswith("."):
            errores.append("la descripcion no termina en punto")
        if descripcion[0].isupper():
            avisos.append("la descripcion va en minuscula segun AGENTS.md (salvo siglas o nombres propios)")

    if len(cabecera) > 72:
        errores.append(f"la cabecera mide {len(cabecera)} caracteres; maximo 72")

    if len(lineas) > 1 and lineas[1].strip() != "":
        errores.append("falta una linea en blanco entre la cabecera y el cuerpo")

    fuera = sorted({c for c in mensaje if ord(c) > 127})
    if fuera:
        errores.append(f"lleva caracteres que no son ASCII: {' '.join(fuera)}. "
                       "Sin tildes ni enes en los mensajes, como el resto del historial")

    for e in errores:
        print(f"  ERROR  {e}")
    for a in avisos:
        print(f"  aviso  {a}")
    if errores:
        print(f"\nEl mensaje NO es valido ({len(errores)} error(es)).")
        return 1
    print("\nEl mensaje es valido." + (" Con avisos." if avisos else ""))
    return 0


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument("--validar", metavar="MENSAJE")
    ap.add_argument("--archivo", type=pathlib.Path, metavar="RUTA")
    ap.add_argument("--raiz", type=pathlib.Path, default=RAIZ, help=argparse.SUPPRESS)
    args = ap.parse_args()

    if args.validar is not None:
        return validar(args.validar, args.raiz)
    if args.archivo:
        return validar(args.archivo.read_text(encoding="utf-8"), args.raiz)
    return analizar(args.raiz)


if __name__ == "__main__":
    sys.exit(main())
