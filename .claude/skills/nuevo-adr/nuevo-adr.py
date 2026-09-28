"""Crea un ADR con el siguiente numero libre, o comprueba los que ya existen.

Un ADR se olvida de dos maneras: no escribiendolo, y escribiendolo sin darle
numero ni fila en el indice. Este script quita la fraccion mecanica para que solo
quede lo que importa, que es el contenido.

Uso:

    python nuevo-adr.py "Titulo de la decision"    crea el archivo y su fila en el indice
    python nuevo-adr.py "Titulo" --dry-run         dice que haria, sin escribir nada
    python nuevo-adr.py --verificar                comprueba todos los ADR existentes

El ADR nuevo nace con estado `propuesto`: aceptarlo es cosa de una persona.
"""

import argparse
import datetime
import pathlib
import re
import sys
import unicodedata

RAIZ = pathlib.Path(__file__).resolve().parents[3]
ESTADOS = {"propuesto", "aceptado", "pendiente", "sustituido"}

PLANTILLA = """# ADR {numero}: {titulo}

- **Estado:** {estado}
- **Fecha:** {fecha}

## Contexto

<!-- Una o dos frases: que situacion obliga a decidir esto. -->

## Decision

<!-- Lo que se decidio, en presente y sin rodeos. -->

## Consecuencias

<!-- Lo que se gana y lo que se paga. Las consecuencias malas tambien van: un ADR
que solo cuenta las buenas no sirve dentro de seis meses. -->
"""


def slug(titulo: str) -> str:
    sin_tildes = unicodedata.normalize("NFKD", titulo).encode("ascii", "ignore").decode()
    s = re.sub(r"[^a-z0-9]+", "-", sin_tildes.lower()).strip("-")
    if len(s) > 60:
        s = s[:60].rsplit("-", 1)[0]
    return s


def numeros_existentes(carpeta: pathlib.Path) -> list[int]:
    return sorted(
        int(m.group(1))
        for f in carpeta.glob("*.md")
        if (m := re.match(r"(\d{4})-", f.name))
    )


def crear(carpeta: pathlib.Path, titulo: str, fecha: str, dry: bool) -> int:
    if not titulo.strip():
        print("El titulo no puede estar vacio.")
        return 2
    if not titulo.isascii():
        print("Aviso: el titulo lleva tildes o enes. Los ADR existentes van sin ellos; "
              "el nombre de archivo saldra sin, pero conviene escribir el titulo igual.")

    numeros = numeros_existentes(carpeta)
    numero = f"{(numeros[-1] + 1) if numeros else 1:04d}"
    nombre = f"{numero}-{slug(titulo)}.md"
    destino = carpeta / nombre
    indice = carpeta / "README.md"

    if destino.exists():
        print(f"Ya existe {destino}. No se sobrescribe.")
        return 1
    if not indice.is_file():
        print(f"No encuentro el indice {indice}.")
        return 1

    fila = f"| [{numero}]({nombre}) | {titulo} | propuesto |"
    lineas = indice.read_text(encoding="utf-8").split("\n")
    ultima_fila = max((i for i, l in enumerate(lineas) if l.startswith("| [")), default=None)
    if ultima_fila is None:
        print("No encuentro la tabla del indice: ninguna fila empieza por '| ['.")
        return 1

    print(f"ADR {numero}: {titulo}")
    print(f"  archivo  {destino.relative_to(RAIZ) if destino.is_relative_to(RAIZ) else destino}")
    print(f"  indice   fila nueva tras la linea {ultima_fila + 1} de {indice.name}")
    if dry:
        print("(--dry-run: no se escribio nada)")
        return 0

    destino.write_text(
        PLANTILLA.format(numero=numero, titulo=titulo, estado="propuesto", fecha=fecha),
        encoding="utf-8", newline="\n",
    )
    lineas.insert(ultima_fila + 1, fila)
    indice.write_text("\n".join(lineas), encoding="utf-8", newline="\n")
    print("Creado. Ahora rellena Contexto, Decision y Consecuencias, y quita los comentarios.")
    return 0


def verificar(carpeta: pathlib.Path) -> int:
    problemas: list[str] = []
    archivos = sorted(f for f in carpeta.glob("*.md") if re.match(r"\d{4}-", f.name))
    indice_txt = (carpeta / "README.md").read_text(encoding="utf-8")

    numeros = [int(f.name[:4]) for f in archivos]
    esperado = list(range(1, len(numeros) + 1))
    if numeros != esperado:
        problemas.append(f"la numeracion tiene huecos o repetidos: {numeros}")

    for f in archivos:
        txt = f.read_text(encoding="utf-8")
        n = f.name[:4]

        m = re.match(r"# ADR (\d{4}): (.+)", txt)
        if not m:
            problemas.append(f"{f.name}: la primera linea debe ser '# ADR NNNN: Titulo'")
        elif m.group(1) != n:
            problemas.append(f"{f.name}: el numero del titulo ({m.group(1)}) no coincide con el del archivo")

        estado = re.search(r"\*\*Estado:\*\*\s*(\w+)", txt)
        if not estado:
            problemas.append(f"{f.name}: falta '**Estado:**'")
        elif estado.group(1) not in ESTADOS:
            problemas.append(f"{f.name}: estado '{estado.group(1)}' no es uno de {sorted(ESTADOS)}")

        if not re.search(r"\*\*Fecha:\*\*\s*\d{4}-\d{2}-\d{2}", txt):
            problemas.append(f"{f.name}: falta '**Fecha:**' con formato AAAA-MM-DD")

        for seccion in ("Contexto", "Decision", "Consecuencias"):
            if not re.search(rf"(?m)^## {seccion}\s*$", txt):
                problemas.append(f"{f.name}: falta la seccion '## {seccion}'")

        if "<!--" in txt:
            problemas.append(f"{f.name}: quedan comentarios de la plantilla sin rellenar")

        # [ \t]* y no \s*: \s consume el salto de linea, y en la ultima fila del
        # archivo eso deja el estado vacio y da una falsa alarma.
        fila = re.search(rf"(?m)^\| \[{n}\]\({re.escape(f.name)}\) \|.*\|[ \t]*$", indice_txt)
        if not fila:
            problemas.append(f"{f.name}: falta su fila en el indice, o apunta a otro archivo")
        elif estado:
            estado_indice = re.sub(r"[*\s]", "", fila.group(0).rstrip("| ").split("|")[-1])
            if estado_indice != estado.group(1):
                problemas.append(
                    f"{f.name}: el estado del archivo ({estado.group(1)}) no coincide con el del indice ({estado_indice})")

        for destino in re.findall(r"\]\(([^)#]+\.md)(?:#[^)]*)?\)", txt):
            if not destino.startswith("http") and not (carpeta / destino).resolve().exists():
                problemas.append(f"{f.name}: enlace roto a {destino}")

    for n, nombre in re.findall(r"(?m)^\| \[(\d{4})\]\(([^)]+)\)", indice_txt):
        if not (carpeta / nombre).exists():
            problemas.append(f"el indice apunta a {nombre}, que no existe")

    if problemas:
        for p in problemas:
            print(f"  FALLA  {p}")
        print(f"\n{len(problemas)} problemas en {len(archivos)} ADR.")
        return 1
    print(f"Los {len(archivos)} ADR estan bien: numeracion, formato, indice y enlaces.")
    return 0


def main() -> int:
    # Este script repite el titulo que le pasan. En Windows, con la salida por una
    # tuberia, Python usa cp1252 y un titulo con tilde sale en un codigo que quien
    # lee no sabe decodificar. UTF-8 siempre.
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument("titulo", nargs="?")
    ap.add_argument("--verificar", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--fecha", default=datetime.date.today().isoformat(), help="AAAA-MM-DD; por defecto, hoy")
    ap.add_argument("--dir", type=pathlib.Path, default=RAIZ / "docs" / "adr", help=argparse.SUPPRESS)
    args = ap.parse_args()

    if args.verificar:
        return verificar(args.dir)
    if not args.titulo:
        ap.error("indica el titulo, o usa --verificar")
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", args.fecha):
        print("La fecha debe ir como AAAA-MM-DD.")
        return 2
    return crear(args.dir, args.titulo, args.fecha, args.dry_run)


if __name__ == "__main__":
    sys.exit(main())
