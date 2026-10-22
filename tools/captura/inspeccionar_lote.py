#!/usr/bin/env python3
"""Inspecciona las fotos de un lote de calibracion: perfil ICC, EXIF y recortes.

Es el equivalente de `exiftool` que pide la spec (criterio: "en iPhone, la foto
conserva su perfil ICC, y el campo perfil_color coincide con el perfil real") para
quien no lo tiene instalado, y comprueba de paso lo que solo se puede ver con fotos
reales salidas de un telefono. Solo lee, y solo usa la libreria estandar.

Acepta el .zip exportado por la app, o la carpeta ya importada a la boveda. Para cada
toma mira:

- la FOTO (JPEG): dimensiones, orientacion EXIF, ISO, tiempo de exposicion, balance de
  blancos y el perfil ICC con su nombre;
- el RECORTE (PNG): dimensiones, tipo de color, y que NO lleve perfil incrustado;
- el JSON: que `perfil_color` diga lo mismo que el perfil real de la foto, y que el
  recuadro del rostro quepa en la foto ya orientada (si no cabe, la orientacion se
  manejo mal en algun paso);
- el espejo de la camara frontal (`camara.espejo`): solo se cuenta, no se juzga.

Salida 0 si no hay nada que senalar; 1 si hay hallazgos; 2 si el uso es incorrecto.
La foto es siempre JPEG: un .heic no es un nombre valido de toma.
"""

from __future__ import annotations

import argparse
import json
import re
import struct
import sys
import zipfile
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

NOMBRE_ARCHIVO = re.compile(
    r"(?P<base>P[1-6]_(?:VEN|LEDC|LEDF|MIX|BAJ)_D[1-3]_R[1-3]_[GN])"
    r"(?P<resto>\.json|_foto\.jpg|_recorte\.png)"
)
PERFIL_SUPUESTO = "sin perfil (se asume sRGB)"
PERFIL_SIN_NOMBRE = "perfil ICC sin nombre"
PERFIL_DEL_RECORTE = "sRGB (convertido por la app)"


# --------------------------------------------------------------------------- #
# JPEG: dimensiones, EXIF y perfil ICC
# --------------------------------------------------------------------------- #


@dataclass
class InfoJpeg:
    ancho: int | None = None
    alto: int | None = None
    orientacion: int | None = None
    iso: int | None = None
    exposicion: float | None = None
    balance_blancos: int | None = None
    perfil: bytes | None = None
    problemas: list[str] = field(default_factory=list)


def _tiff(datos: bytes, info: InfoJpeg) -> None:
    """Lee los tags que interesan del TIFF embebido en el APP1 de Exif."""
    if len(datos) < 8 or datos[:2] not in (b"II", b"MM"):
        info.problemas.append("EXIF con cabecera TIFF invalida")
        return
    e = "<" if datos[:2] == b"II" else ">"
    if struct.unpack(e + "H", datos[2:4])[0] != 42:
        info.problemas.append("EXIF con numero magico TIFF invalido")
        return

    def ifd(offset: int) -> dict[int, tuple[int, int, int]]:
        # tag -> (tipo, cantidad, posicion del valor)
        if offset + 2 > len(datos):
            return {}
        n = struct.unpack(e + "H", datos[offset:offset + 2])[0]
        entradas = {}
        for i in range(n):
            base = offset + 2 + 12 * i
            if base + 12 > len(datos):
                break
            tag, tipo, cuenta = struct.unpack(e + "HHI", datos[base:base + 8])
            entradas[tag] = (tipo, cuenta, base + 8)
        return entradas

    tamanos = {1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 7: 1, 9: 4, 10: 8}

    def valor(entrada: tuple[int, int, int]) -> float | int | None:
        tipo, cuenta, pos = entrada
        total = tamanos.get(tipo, 0) * cuenta
        if total == 0:
            return None
        donde = pos if total <= 4 else struct.unpack(e + "I", datos[pos:pos + 4])[0]
        if donde + total > len(datos):
            return None
        if tipo == 3:
            return struct.unpack(e + "H", datos[donde:donde + 2])[0]
        if tipo == 4:
            return struct.unpack(e + "I", datos[donde:donde + 4])[0]
        if tipo == 5:
            num, den = struct.unpack(e + "II", datos[donde:donde + 8])
            return num / den if den else None
        return None

    raiz = ifd(struct.unpack(e + "I", datos[4:8])[0])
    if 0x0112 in raiz:
        v = valor(raiz[0x0112])
        info.orientacion = int(v) if v is not None else None
    if 0x8769 in raiz:
        sub = valor(raiz[0x8769])
        if sub is not None:
            exif = ifd(int(sub))
            if 0x8827 in exif and (v := valor(exif[0x8827])) is not None:
                info.iso = int(v)
            if 0x829A in exif:
                info.exposicion = valor(exif[0x829A])  # type: ignore[assignment]
            if 0xA403 in exif and (v := valor(exif[0xA403])) is not None:
                info.balance_blancos = int(v)


def leer_jpeg(datos: bytes) -> InfoJpeg:
    info = InfoJpeg()
    if not datos.startswith(b"\xff\xd8"):
        info.problemas.append("no es un JPEG")
        return info
    fragmentos: dict[int, bytes] = {}
    i = 2
    while i + 4 <= len(datos):
        if datos[i] != 0xFF:
            info.problemas.append(f"marcador JPEG esperado en el byte {i}")
            break
        m = datos[i + 1]
        if m == 0xFF:
            i += 1
            continue
        if m in (0xD8, 0x01) or 0xD0 <= m <= 0xD7:
            i += 2
            continue
        if m in (0xDA, 0xD9):
            break
        largo = struct.unpack(">H", datos[i + 2:i + 4])[0]
        cuerpo = datos[i + 4:i + 2 + largo]
        if m == 0xE1 and cuerpo.startswith(b"Exif\x00\x00"):
            _tiff(cuerpo[6:], info)
        elif m == 0xE2 and cuerpo.startswith(b"ICC_PROFILE\x00") and len(cuerpo) >= 14:
            fragmentos[cuerpo[12]] = cuerpo[14:]
        elif 0xC0 <= m <= 0xCF and m not in (0xC4, 0xC8, 0xCC) and len(cuerpo) >= 5:
            info.alto, info.ancho = struct.unpack(">HH", cuerpo[1:5])
        i += 2 + largo
    if fragmentos:
        info.perfil = b"".join(fragmentos[k] for k in sorted(fragmentos))
    return info


def descripcion_de_perfil(perfil: bytes) -> str | None:
    """Nombre del perfil ICC (tag `desc`, v2 o v4), o None si no se puede leer."""
    if len(perfil) < 132 or perfil[36:40] != b"acsp":
        return None
    try:
        n = struct.unpack(">I", perfil[128:132])[0]
        for k in range(n):
            base = 132 + 12 * k
            firma = perfil[base:base + 4]
            inicio, largo = struct.unpack(">II", perfil[base + 4:base + 12])
            if firma != b"desc":
                continue
            tag = perfil[inicio:inicio + largo]
            if tag[:4] == b"desc":
                cuenta = struct.unpack(">I", tag[8:12])[0]
                texto = tag[12:12 + cuenta].split(b"\x00")[0].decode("latin-1").strip()
                return texto or None
            if tag[:4] == b"mluc":
                longitud, desplazamiento = struct.unpack(">II", tag[20:28])
                texto = tag[desplazamiento:desplazamiento + longitud].decode("utf-16-be").strip()
                return texto or None
    except (struct.error, UnicodeDecodeError, IndexError):
        return None
    return None


# --------------------------------------------------------------------------- #
# PNG
# --------------------------------------------------------------------------- #


@dataclass
class InfoPng:
    ancho: int | None = None
    alto: int | None = None
    profundidad: int | None = None
    tipo_de_color: int | None = None
    chunks_de_color: list[str] = field(default_factory=list)
    problemas: list[str] = field(default_factory=list)


def leer_png(datos: bytes) -> InfoPng:
    info = InfoPng()
    if not datos.startswith(b"\x89PNG\r\n\x1a\n"):
        info.problemas.append("no es un PNG")
        return info
    i = 8
    while i + 8 <= len(datos):
        largo, tipo = struct.unpack(">I4s", datos[i:i + 8])
        cuerpo = datos[i + 8:i + 8 + largo]
        nombre = tipo.decode("latin-1")
        if nombre == "IHDR" and len(cuerpo) >= 13:
            info.ancho, info.alto, info.profundidad, info.tipo_de_color = (
                struct.unpack(">IIBB", cuerpo[:10])
            )
        if nombre in ("iCCP", "sRGB", "gAMA", "cHRM"):
            info.chunks_de_color.append(nombre)
        if nombre == "IEND":
            break
        i += 12 + largo
    return info


# --------------------------------------------------------------------------- #
# Inspeccion del lote
# --------------------------------------------------------------------------- #


@dataclass
class Toma:
    base: str
    foto: str | None = None
    recorte: str | None = None
    json_: str | None = None


@dataclass
class Informe:
    lineas: list[str] = field(default_factory=list)
    hallazgos: list[str] = field(default_factory=list)
    resumen: dict = field(default_factory=dict)


def _leer_origen(origen: Path) -> dict[str, bytes]:
    """Los archivos del lote por nombre, desde un zip o una carpeta."""
    if origen.is_dir():
        return {p.name: p.read_bytes() for p in sorted(origen.iterdir()) if p.is_file()}
    with zipfile.ZipFile(origen) as z:
        return {i.filename: z.read(i) for i in z.infolist() if not i.is_dir()}


def _dimensiones_orientadas(ancho: int, alto: int, orientacion: int | None) -> tuple[int, int]:
    """Dimensiones de la foto ya orientada: EXIF 5 a 8 intercambia ancho y alto."""
    return (alto, ancho) if orientacion in (5, 6, 7, 8) else (ancho, alto)


def inspeccionar(origen: Path) -> Informe:
    archivos = _leer_origen(origen)
    tomas: dict[str, Toma] = {}
    for nombre in archivos:
        m = NOMBRE_ARCHIVO.fullmatch(nombre)
        if not m:
            continue
        t = tomas.setdefault(m["base"], Toma(m["base"]))
        resto = m["resto"]
        if resto == ".json":
            t.json_ = nombre
        elif resto == "_recorte.png":
            t.recorte = nombre
        else:
            t.foto = nombre

    inf = Informe()
    orientaciones: Counter = Counter()
    perfiles: Counter = Counter()
    con = {"icc": 0, "iso": 0, "exposicion": 0, "wb": 0}
    espejos: Counter = Counter()
    jpegs = 0
    dims_recorte: list[tuple[int, int]] = []

    for base in sorted(tomas):
        t = tomas[base]
        def hallazgo(texto: str, base: str = base) -> None:
            inf.hallazgos.append(f"{base}: {texto}")

        meta = None
        if t.json_:
            try:
                meta = json.loads(archivos[t.json_].decode("utf-8"))
            except (ValueError, UnicodeDecodeError):
                hallazgo("el JSON no se puede leer")
        if t.foto is None or t.recorte is None or meta is None:
            hallazgo("faltan archivos de la toma")
            continue

        espejo = (meta.get("camara") or {}).get("espejo")
        espejos["null" if espejo is None else str(espejo).lower()] += 1

        # --- foto ---
        jpegs += 1
        j = leer_jpeg(archivos[t.foto])
        for p in j.problemas:
            hallazgo(f"foto: {p}")
        orientaciones[j.orientacion] += 1
        if j.iso is not None:
            con["iso"] += 1
        if j.exposicion is not None:
            con["exposicion"] += 1
        if j.balance_blancos is not None:
            con["wb"] += 1

        nombre_icc = descripcion_de_perfil(j.perfil) if j.perfil else None
        if j.perfil:
            con["icc"] += 1
            esperado = nombre_icc or PERFIL_SIN_NOMBRE
        else:
            esperado = PERFIL_SUPUESTO
        perfiles[nombre_icc if j.perfil else "(sin perfil)"] += 1
        declarado = (meta.get("perfil_color") or {}).get("foto")
        if declarado != esperado:
            hallazgo(
                f"perfil_color.foto dice {declarado!r} pero el perfil real de la foto "
                f"es {esperado!r}"
            )

        if j.ancho and j.alto:
            ancho, alto = _dimensiones_orientadas(j.ancho, j.alto, j.orientacion)
            bbox = (meta.get("rostro") or {}).get("bbox")
            if isinstance(bbox, list) and len(bbox) == 4:
                izq, arr, der, aba = bbox
                if izq < 0 or arr < 0 or der > ancho + 1 or aba > alto + 1 or der <= izq or aba <= arr:
                    hallazgo(
                        f"el recuadro del rostro {bbox} no cabe en la foto orientada "
                        f"{ancho}x{alto} (EXIF {j.orientacion}): revisar la orientacion"
                    )
        inf.lineas.append(
            f"{base}: foto {j.ancho}x{j.alto} EXIF={j.orientacion} ISO={j.iso} "
            f"exp={j.exposicion} WB={j.balance_blancos} ICC={nombre_icc if j.perfil else 'no'}"
        )

        # --- recorte ---
        p = leer_png(archivos[t.recorte])
        for pr in p.problemas:
            hallazgo(f"recorte: {pr}")
        if p.ancho:
            dims_recorte.append((p.ancho, p.alto or 0))
        if "iCCP" in p.chunks_de_color:
            hallazgo("el recorte lleva un perfil ICC incrustado (no deberia: sale ya en sRGB)")
        if p.tipo_de_color not in (None, 2) or p.profundidad not in (None, 8):
            hallazgo(
                f"el recorte no es RGB de 8 bits (tipo de color {p.tipo_de_color}, "
                f"profundidad {p.profundidad})"
            )
        if (meta.get("perfil_color") or {}).get("recorte") != PERFIL_DEL_RECORTE:
            hallazgo(
                f"perfil_color.recorte dice {(meta.get('perfil_color') or {}).get('recorte')!r}, "
                f"se esperaba {PERFIL_DEL_RECORTE!r}"
            )

    inf.resumen = {
        "tomas": len(tomas),
        "fotos_jpeg": jpegs,
        "con_perfil_icc": con["icc"],
        "con_iso": con["iso"],
        "con_exposicion": con["exposicion"],
        "con_balance_blancos": con["wb"],
        "orientaciones_exif": dict(orientaciones),
        "espejo_camara": dict(espejos),
        "perfiles": dict(perfiles),
        "recorte_ancho_min_max": (
            (min(d[0] for d in dims_recorte), max(d[0] for d in dims_recorte))
            if dims_recorte else None
        ),
    }
    return inf


def principal(argv: list[str] | None = None, salida=None) -> int:
    salida = salida or sys.stdout
    p = argparse.ArgumentParser(
        prog="inspeccionar_lote.py",
        description="Inspecciona el perfil ICC, el EXIF y los recortes de un lote.",
    )
    p.add_argument("origen", type=Path, help="el .zip exportado o la carpeta ya importada")
    p.add_argument("--silencioso", action="store_true", help="solo el resumen y los hallazgos")
    args = p.parse_args(argv)
    if not args.origen.exists():
        print(f"No existe {args.origen}", file=salida)
        return 2
    try:
        inf = inspeccionar(args.origen)
    except (zipfile.BadZipFile, OSError) as e:
        print(f"No se pudo leer {args.origen}: {e}", file=salida)
        return 2

    if not args.silencioso:
        for linea in inf.lineas:
            print(linea, file=salida)
        print(file=salida)
    r = inf.resumen
    print(f"Tomas: {r['tomas']}   fotos JPEG: {r['fotos_jpeg']}", file=salida)
    print(f"Con perfil ICC: {r['con_perfil_icc']}   perfiles: {r['perfiles']}", file=salida)
    print(
        f"Con ISO: {r['con_iso']}   con exposicion: {r['con_exposicion']}   "
        f"con balance de blancos: {r['con_balance_blancos']}",
        file=salida,
    )
    print(f"Orientaciones EXIF de las fotos: {r['orientaciones_exif']}", file=salida)
    print(f"Espejo de la camara frontal (camara.espejo): {r['espejo_camara']}", file=salida)
    print(f"Ancho de los recortes (min, max): {r['recorte_ancho_min_max']}", file=salida)
    if inf.hallazgos:
        print(f"\nHALLAZGOS ({len(inf.hallazgos)}):", file=salida)
        for h in inf.hallazgos:
            print(f"  - {h}", file=salida)
        return 1
    print("\nSin hallazgos.", file=salida)
    return 0


if __name__ == "__main__":
    sys.exit(principal())
