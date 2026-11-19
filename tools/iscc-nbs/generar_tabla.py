"""Genera la tabla ISCC-NBS de la app: 267 bloques en Lab D65 y su categoria de color.

Entrada: centroides_nist_1958.csv, transcrito de Kelly (1958), "Central Notations for the
Revised ISCC-NBS Color-Name Blocks", J. Res. NBS 61(5), RP2911. Dominio publico en EE. UU.
Salida: client/assets/color/iscc_nbs.json y la misma copia en el Core
(services/core/src/main/resources/colores/), que la usa para ajustar las categorias.

Munsell a Lab con colour-science (BSD-3). No se usa munsellinterpol, que es GPL (#58).
La renotacion Munsell esta referida al iluminante C: se pasa a D65 con Bradford, igual que
hace la app con el D50 de los perfiles ICC, y el Lab lleva el blanco D65 de la app.

La categoria sale de reglas sobre el nombre del bloque (tono + modificador), escritas abajo
en REGLAS. Se revisan a mano: es la tabla que pide la issue, generada por reglas y revisada
por el equipo. Cambiar una categoria es cambiar una linea de REGLAS y regenerar.

Uso (una vez, no lo corre CI):
    uv venv && uv pip install colour-science==0.4.7 scipy
    uv run python tools/iscc-nbs/generar_tabla.py            # escribe el JSON
    uv run python tools/iscc-nbs/generar_tabla.py --comprobar  # falla si el JSON no coincide
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
import warnings
from pathlib import Path

warnings.filterwarnings("ignore")  # colour avisa de dependencias opcionales que no se usan

import colour  # noqa: E402
import numpy as np  # noqa: E402

AQUI = Path(__file__).resolve().parent
CSV = AQUI / "centroides_nist_1958.csv"
RAIZ = AQUI.parents[1]
SALIDAS = (
    RAIZ / "client" / "assets" / "color" / "iscc_nbs.json",
    RAIZ / "services" / "core" / "src" / "main" / "resources" / "colores" / "iscc_nbs.json",
)

# Las 20 categorias oficiales (CategoriaColor del Core). La app usa los mismos nombres.
CATEGORIAS = (
    "NEGRO", "BLANCO", "GRIS", "BEIGE", "CAFE", "VINOTINTO", "ROJO", "ROSADO", "FUCSIA",
    "NARANJA", "AMARILLO", "MOSTAZA", "VERDE_OLIVA", "VERDE", "TURQUESA", "CELESTE", "AZUL",
    "AZUL_MARINO", "MORADO", "LILA",
)

# Tono -> {modificador: categoria}. "*" es el valor por defecto del tono.
# Los blancos, grises y negros (y los "blackish") se resuelven antes, en categoria().
REGLAS: dict[str, dict[str, str]] = {
    "pink": {"*": "ROSADO"},
    "red": {
        "*": "ROJO",
        "deep": "VINOTINTO", "very deep": "VINOTINTO", "dark": "VINOTINTO",
        "very dark": "VINOTINTO", "dark grayish": "VINOTINTO",
        "light grayish": "ROSADO",
    },
    "yellowish pink": {"*": "ROSADO", "grayish": "BEIGE"},
    "brownish pink": {"*": "BEIGE"},
    # El rojo de pantalla (sRGB) cae en reddish orange, no en red: los "red" de ISCC-NBS
    # tiran a carmesi. Por eso los intensos van a ROJO.
    "reddish orange": {
        "*": "NARANJA",
        "vivid": "ROJO", "strong": "ROJO", "deep": "ROJO",
        "dark": "CAFE", "grayish": "CAFE",
    },
    "reddish brown": {"*": "CAFE", "light grayish": "BEIGE"},
    "orange": {"*": "NARANJA"},
    "brownish orange": {"*": "NARANJA"},
    "brown": {"*": "CAFE", "light grayish": "BEIGE"},
    "orange yellow": {
        "*": "AMARILLO",
        "vivid": "NARANJA", "strong": "NARANJA",
        "deep": "MOSTAZA", "dark": "MOSTAZA", "moderate": "MOSTAZA",
        "pale": "BEIGE",
    },
    "yellowish brown": {"*": "CAFE", "light": "BEIGE", "light grayish": "BEIGE"},
    "yellow": {
        "*": "AMARILLO",
        "deep": "MOSTAZA", "dark": "MOSTAZA", "dark grayish": "MOSTAZA",
        "grayish": "BEIGE", "pale": "BEIGE",  # pale yellow: el crema
    },
    "olive brown": {"*": "CAFE", "light": "MOSTAZA"},
    "greenish yellow": {
        "*": "AMARILLO",
        "deep": "VERDE_OLIVA", "dark": "VERDE_OLIVA", "grayish": "VERDE_OLIVA",
        "pale": "BEIGE",
    },
    "olive": {"*": "VERDE_OLIVA"},
    "yellow green": {"*": "VERDE"},
    "olive green": {"*": "VERDE_OLIVA"},
    "yellowish green": {"*": "VERDE"},
    "green": {"*": "VERDE"},
    "bluish green": {
        "*": "TURQUESA",
        "deep": "VERDE", "dark": "VERDE", "very dark": "VERDE",
    },
    "greenish blue": {
        "*": "TURQUESA",
        "very light": "CELESTE", "light": "CELESTE",
        "deep": "AZUL", "dark": "AZUL", "very dark": "AZUL_MARINO",
    },
    "blue": {
        "*": "AZUL",
        "very light": "CELESTE", "light": "CELESTE", "very pale": "CELESTE", "pale": "CELESTE",
        "deep": "AZUL_MARINO", "dark": "AZUL_MARINO",
        "dark grayish": "GRIS",  # el gris carbon cae aqui
    },
    "purplish blue": {
        "*": "AZUL",
        "very light": "CELESTE", "light": "CELESTE",
        "very pale": "LILA", "pale": "LILA",
        "deep": "AZUL_MARINO", "dark": "AZUL_MARINO",
    },
    "violet": {
        "*": "MORADO",
        "very light": "LILA", "light": "LILA", "very pale": "LILA", "pale": "LILA",
    },
    "purple": {
        "*": "MORADO",
        "very light": "LILA", "light": "LILA", "very pale": "LILA", "pale": "LILA",
    },
    "reddish purple": {
        "*": "MORADO",
        "vivid": "FUCSIA", "strong": "FUCSIA",
        "light": "LILA", "pale": "LILA",
    },
    "purplish pink": {
        "*": "ROSADO",
        "brilliant": "FUCSIA", "strong": "FUCSIA", "deep": "FUCSIA",
    },
    "purplish red": {
        "*": "VINOTINTO",
        "vivid": "FUCSIA", "strong": "FUCSIA", "moderate": "ROJO",
        "light grayish": "ROSADO",
    },
}

# Del modificador mas largo al mas corto, para que "very dark" gane a "dark".
MODIFICADORES = sorted(
    (
        "vivid", "brilliant", "strong", "deep", "very deep", "very light", "light",
        "moderate", "dark", "very dark", "very pale", "pale", "light grayish", "grayish",
        "dark grayish", "blackish",
    ),
    key=len,
    reverse=True,
)


def categoria(nombre: str) -> str:
    """Categoria de un bloque a partir de su nombre ISCC-NBS."""
    if nombre == "white" or nombre.endswith(" white"):
        return "BLANCO"
    if nombre == "black" or nombre.endswith(" black") or nombre.startswith("blackish "):
        return "NEGRO"
    if nombre.endswith("gray"):  # light gray, reddish gray, dark olive gray...
        return "GRIS"
    modificador, tono = "", nombre
    for m in MODIFICADORES:
        if nombre.startswith(m + " "):
            modificador, tono = m, nombre[len(m) + 1:]
            break
    if tono not in REGLAS:
        raise ValueError(f"sin regla para el tono {tono!r} ({nombre!r})")
    reglas = REGLAS[tono]
    return reglas.get(modificador, reglas["*"])


NOTACION = re.compile(
    r"^(?:(?P<h>\d+(?:\.\d*)?)[+-]?(?P<familia>R|YR|Y|GY|G|BG|B|PB|P|RP)"
    r"|N) (?P<v>\d+(?:\.\d+)?)[+-]?/(?P<c>\d+(?:\.\d+)?)?[+-]?$"
)


def normalizar(publicada: str) -> tuple[str, float, float, float, str | None]:
    """'9.5+R 5.5/15.5+' -> ('9.5R 5.5/15.5', ...). El +/- del original (incertidumbre en
    el siguiente decimal) se descarta."""
    m = NOTACION.match(publicada)
    if not m:
        raise ValueError(f"notacion no reconocida: {publicada!r}")
    v = float(m["v"])
    if m["familia"] is None:
        return f"N{v:g}", 0.0, v, 0.0, None
    h, c = float(m["h"]), float(m["c"])
    return f"{h:g}{m['familia']} {v:g}/{c:g}", h, v, c, m["familia"]


def munsell_a_xyY(h: float, v: float, c: float, familia: str | None) -> tuple[np.ndarray, list[str]]:
    """xyY (iluminante C) de una notacion. La renotacion no cubre los valores < 1 ni los
    cromas mas alla de lo medido: ahi se ajusta y se anota el ajuste."""
    ajustes: list[str] = []
    if familia is None:
        y = colour.notation.munsell.luminance_ASTMD1535(v) / 100
        x, yy = colour.CCS_ILLUMINANTS["CIE 1931 2 Degree Standard Observer"]["C"]
        return np.array([x, yy, y]), ajustes
    v_cromaticidad = v
    if v < 1:
        # Por debajo de 1 la cromaticidad se toma de V=1 y la luminancia del valor real.
        v_cromaticidad = 1.0
        ajustes.append(f"cromaticidad de V=1 (V={v:g} fuera de la renotacion)")
    c_usado = c
    while True:
        try:
            xyY = colour.munsell_colour_to_xyY(f"{h:g}{familia} {v_cromaticidad:g}/{c_usado:g}")
            break
        except (AssertionError, ValueError):
            c_usado = round(c_usado - 0.5, 1)
            if c_usado <= 0:
                raise
    if c_usado != c:
        ajustes.append(f"croma {c:g} -> {c_usado:g} (fuera de la renotacion)")
    if v_cromaticidad != v:
        xyY = np.array([xyY[0], xyY[1], colour.notation.munsell.luminance_ASTMD1535(v) / 100])
    return np.asarray(xyY), ajustes


def lab_d65(xyY: np.ndarray) -> list[float]:
    xyz_c = colour.xyY_to_XYZ(xyY)
    blanco_c = colour.xy_to_XYZ(colour.CCS_ILLUMINANTS["CIE 1931 2 Degree Standard Observer"]["C"])
    blanco_d65 = np.array([0.95047, 1.0, 1.08883])  # el de la app (conversion.dart)
    xyz_d65 = colour.adaptation.chromatic_adaptation_VonKries(
        xyz_c, blanco_c, blanco_d65, transform="Bradford"
    )
    lab = colour.XYZ_to_Lab(xyz_d65, colour.XYZ_to_xy(blanco_d65))
    return [round(float(x), 2) + 0.0 for x in lab]  # +0.0: sin -0.0 en el JSON


def generar() -> dict:
    bloques = []
    with CSV.open(encoding="utf-8", newline="") as f:
        for fila in csv.DictReader(f):
            notacion, h, v, c, familia = normalizar(fila["notacion_publicada"])
            xyY, ajustes = munsell_a_xyY(h, v, c, familia)
            bloque = {
                "numero": int(fila["numero"]),
                "nombre": fila["nombre"],
                "munsell": notacion,
                "lab": lab_d65(xyY),
                "categoria": categoria(fila["nombre"]),
            }
            if ajustes:
                bloque["ajustes"] = ajustes
            bloques.append(bloque)
    if [b["numero"] for b in bloques] != list(range(1, 268)):
        raise ValueError("el CSV no tiene los 267 bloques en orden")
    usadas = {b["categoria"] for b in bloques}
    if usadas != set(CATEGORIAS):
        raise ValueError(f"categorias sin bloque: {set(CATEGORIAS) - usadas}")
    return {
        "fuente": "Kelly 1958, J. Res. NBS 61(5) RP2911, tabla 1 (centroides ISCC-NBS)",
        "conversion": "colour-science 0.4.7, renotacion Munsell (C) -> Bradford -> Lab D65",
        "version": 1,
        "categorias": list(CATEGORIAS),
        "bloques": bloques,
    }


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--comprobar", action="store_true", help="no escribe; falla si difiere")
    args = p.parse_args()
    texto = json.dumps(generar(), ensure_ascii=False, indent=1) + "\n"
    if args.comprobar:
        distintas = [s for s in SALIDAS if s.read_text(encoding="utf-8") != texto]
        for s in distintas:
            print(f"{s} no coincide con lo generado", file=sys.stderr)
        if not distintas:
            print("OK")
        return 1 if distintas else 0
    for s in SALIDAS:
        s.parent.mkdir(parents=True, exist_ok=True)
        s.write_text(texto, encoding="utf-8", newline="\n")
        print(f"escrito {s}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
