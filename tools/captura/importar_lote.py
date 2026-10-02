#!/usr/bin/env python3
"""Importa un lote de tomas de calibracion a la boveda Cryptomator.

Es el lado del computador del modo de captura de pruebas
(docs/spec-modo-captura-pruebas.md, seccion 6). La app exporta un .zip con las
tomas y un manifiesto.json; este script lo comprueba entero y, solo si todo
cuadra, lo copia a la boveda.

Que hace, en este orden:

1. Verifica el zip SIN escribir nada: nombres seguros, SHA-256 de cada archivo
   contra el manifiesto, hash global, cada JSON contra el esquema 1, y que cada
   JSON y sus dos archivos se correspondan.
2. Si algo falla, no copia nada y lo cuenta todo (no solo el primer problema).
3. Si todo cuadra, copia a una carpeta temporal dentro de la boveda, vuelve a
   leer lo copiado para comprobarlo, y solo entonces la renombra. Nunca queda un
   destino a medias, y nunca sobrescribe.
4. Muestra un resumen y el hash global. Los 8 primeros caracteres son lo que se
   teclea en la app para habilitar "Borrar".

Solo usa la libreria estandar. La ruta de la boveda va en un archivo de
configuracion FUERA del repositorio (ver README.md); el script se niega a leer
una configuracion, o a escribir en una boveda, que este dentro de un repositorio.

Codigos de salida: 0 todo bien; 1 el lote no paso la verificacion o la copia
fallo (no se copio nada); 2 uso o configuracion incorrectos.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import sys
import zipfile
import zlib
from dataclasses import dataclass, field
from pathlib import Path

ESQUEMA_METADATOS = 1
ESQUEMA_MANIFIESTO = 1
NOMBRE_MANIFIESTO = "manifiesto.json"

# Topes contra un zip hostil o roto: un lote real son decenas de archivos y unos
# cientos de megabytes.
MAX_ARCHIVOS = 2000
MAX_BYTES = 4 * 1024**3
MAX_BYTES_JSON = 1024 * 1024
BLOQUE = 1024 * 1024

LUCES = ("VEN", "LEDC", "LEDF", "MIX", "BAJ")
CELULARES = ("D1", "D2", "D3")
REPETICIONES = ("R1", "R2", "R3")

# Siempre fullmatch: en Python `$` acepta un salto de linea final y "P1\n" pasaria.
SEUDONIMO = re.compile(r"P[1-6]")
NOMBRE_ARCHIVO = re.compile(
    r"(?P<base>P[1-6]_(?:VEN|LEDC|LEDF|MIX|BAJ)_D[1-3]_R[1-3]_[GN])"
    r"(?P<resto>\.json|_foto\.(?:jpg|heic)|_recorte\.png)"
)
FECHA = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}")
SHA256 = re.compile(r"[0-9a-f]{64}")
COMPONENTE_DE_RUTA = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")


# Todo lo que `zipfile` puede lanzar con un archivo roto o hostil: un nombre
# corrupto da UnicodeDecodeError (un ValueError), un deflate roto da zlib.error,
# y una compresion rara da NotImplementedError. Ninguno debe llegar al usuario
# como un traceback: se informan como un problema del lote.
ERRORES_DE_ZIP = (
    zipfile.BadZipFile,
    zipfile.LargeZipFile,
    OSError,
    ValueError,
    RuntimeError,
    EOFError,
    NotImplementedError,
    zlib.error,
)


class ErrorDeConfiguracion(Exception):
    """La configuracion o los argumentos no sirven. Salida 2."""


class ErrorDeCopia(Exception):
    """La copia fallo; no quedo nada a medias. Salida 1."""


# --------------------------------------------------------------------------- #
# Hash global y esquema
# --------------------------------------------------------------------------- #


def calcular_hash_global(entradas: list[tuple[str, str]]) -> str:
    """SHA-256 de las lineas "<sha256>  <ruta>\\n" ordenadas por ruta.

    `entradas` son pares (ruta, sha256). Dos espacios, como `sha256sum`; orden
    ordinal. Es la misma formula que `calcularHashGlobal` en la app.
    """
    texto = "".join(
        f"{sha}  {ruta}\n" for ruta, sha in sorted(entradas, key=lambda e: e[0])
    )
    return hashlib.sha256(texto.encode("utf-8")).hexdigest()


def _es_entero(valor: object) -> bool:
    return isinstance(valor, int) and not isinstance(valor, bool)


def _es_numero(valor: object) -> bool:
    return isinstance(valor, (int, float)) and not isinstance(valor, bool)


def _claves(p: list[str], donde: str, objeto: dict, esperadas: set[str]) -> None:
    for k in sorted(esperadas - objeto.keys()):
        p.append(f'{donde}: falta la clave "{k}"')
    for k in sorted(objeto.keys() - esperadas):
        p.append(f'{donde}: clave no prevista "{k}"')


def _objeto(p: list[str], nombre: str, valor: object) -> dict | None:
    if isinstance(valor, dict):
        return valor
    p.append(f"{nombre} debe ser un objeto")
    return None


def validar_metadatos(json_toma: object) -> list[str]:
    """Valida el JSON de una toma contra el esquema 1. Una frase por problema.

    Es el espejo de `validarMetadatos` en la app (metadatos.dart). Estricto: no
    admite claves de mas ni de menos.
    """
    p: list[str] = []
    if not isinstance(json_toma, dict):
        return ["no es un objeto JSON"]
    j = json_toma

    _claves(
        p, "raiz", j,
        {"esquema", "seudonimo", "luz", "repeticion", "tarjeta_gris", "fecha_hora",
         "celular", "pantalla", "camara", "rostro", "perfil_color", "archivos"},
    )

    if not _es_entero(j.get("esquema")) or j.get("esquema") != ESQUEMA_METADATOS:
        p.append(f"esquema debe ser {ESQUEMA_METADATOS}")

    seudonimo = j.get("seudonimo")
    luz = j.get("luz")
    repeticion = j.get("repeticion")
    if not isinstance(seudonimo, str) or not SEUDONIMO.fullmatch(seudonimo):
        p.append("seudonimo debe ser P1 a P6")
    if luz not in LUCES:
        p.append("luz no es una de VEN, LEDC, LEDF, MIX, BAJ")
    if repeticion not in REPETICIONES:
        p.append("repeticion no es R1, R2 o R3")
        repeticion = None
    if not isinstance(j.get("tarjeta_gris"), bool):
        p.append("tarjeta_gris debe ser booleano")
    elif repeticion is not None and j["tarjeta_gris"] != (repeticion == "R1"):
        p.append("tarjeta_gris no corresponde a la repeticion (solo R1 lleva tarjeta)")
    fecha = j.get("fecha_hora")
    if not isinstance(fecha, str) or not FECHA.fullmatch(fecha):
        p.append("fecha_hora debe ser ISO 8601 con desfase, p. ej. 2026-10-15T15:42:07-05:00")

    codigo_celular = None
    celular = _objeto(p, "celular", j.get("celular"))
    if celular is not None:
        _claves(p, "celular", celular, {"codigo", "modelo", "sistema", "build_app"})
        if celular.get("codigo") not in CELULARES:
            p.append("celular.codigo no es D1, D2 o D3")
        else:
            codigo_celular = celular["codigo"]
        for k in ("modelo", "sistema", "build_app"):
            v = celular.get(k)
            if not isinstance(v, str) or not v:
                p.append(f"celular.{k} debe ser un texto no vacio")

    pantalla = _objeto(p, "pantalla", j.get("pantalla"))
    if pantalla is not None:
        _claves(p, "pantalla", pantalla, {"true_tone_o_night_shift"})
        if not isinstance(pantalla.get("true_tone_o_night_shift"), bool):
            p.append("pantalla.true_tone_o_night_shift debe ser booleano")

    camara = _objeto(p, "camara", j.get("camara"))
    if camara is not None:
        _claves(p, "camara", camara, {"lente", "flash", "parametros"})
        if camara.get("lente") != "frontal":
            p.append('camara.lente debe ser "frontal"')
        if camara.get("flash") != "apagado":
            p.append('camara.flash debe ser "apagado"')
        par = _objeto(p, "camara.parametros", camara.get("parametros"))
        if par is not None:
            _claves(p, "camara.parametros", par, {"exposicion", "iso", "balance_blancos"})
            for k in ("exposicion", "iso"):
                if par.get(k) is not None and not _es_numero(par.get(k)):
                    p.append(f"camara.parametros.{k} debe ser un numero o null")
            bb = par.get("balance_blancos")
            if bb is not None and not isinstance(bb, str):
                p.append("camara.parametros.balance_blancos debe ser un texto o null")

    rostro = _objeto(p, "rostro", j.get("rostro"))
    if rostro is not None:
        _claves(p, "rostro", rostro, {"bbox", "ancho_px"})
        bbox = rostro.get("bbox")
        if not isinstance(bbox, list) or len(bbox) != 4 or not all(_es_numero(v) for v in bbox):
            p.append("rostro.bbox debe ser una lista de 4 numeros")
        ancho = rostro.get("ancho_px")
        if not _es_entero(ancho) or ancho < 0:
            p.append("rostro.ancho_px debe ser un entero mayor o igual a 0")

    perfil = _objeto(p, "perfil_color", j.get("perfil_color"))
    if perfil is not None:
        _claves(p, "perfil_color", perfil, {"foto", "recorte"})
        for k in ("foto", "recorte"):
            v = perfil.get(k)
            if not isinstance(v, str) or not v:
                p.append(f"perfil_color.{k} debe ser un texto no vacio")

    archivos = _objeto(p, "archivos", j.get("archivos"))
    if archivos is not None:
        _claves(p, "archivos", archivos, {"foto", "recorte", "sha256"})
        if (
            isinstance(seudonimo, str) and SEUDONIMO.fullmatch(seudonimo)
            and luz in LUCES and repeticion is not None and codigo_celular is not None
        ):
            marca = "G" if repeticion == "R1" else "N"
            base = f"{seudonimo}_{luz}_{codigo_celular}_{repeticion}_{marca}"
            foto = archivos.get("foto")
            if not isinstance(foto, str) or not re.fullmatch(
                re.escape(base) + r"_foto\.(?:jpg|heic)", foto
            ):
                p.append(f"archivos.foto debe llamarse {base}_foto.jpg (o .heic)")
            if archivos.get("recorte") != f"{base}_recorte.png":
                p.append(f"archivos.recorte debe llamarse {base}_recorte.png")
        sha = _objeto(p, "archivos.sha256", archivos.get("sha256"))
        if sha is not None:
            _claves(p, "archivos.sha256", sha, {"foto", "recorte"})
            for k in ("foto", "recorte"):
                v = sha.get(k)
                if not isinstance(v, str) or not SHA256.fullmatch(v):
                    p.append(f"archivos.sha256.{k} debe ser un SHA-256 en hexadecimal minuscula")
    return p


# --------------------------------------------------------------------------- #
# Verificacion del zip
# --------------------------------------------------------------------------- #


@dataclass
class Resultado:
    problemas: list[str] = field(default_factory=list)
    hash_global: str | None = None
    # (ruta, sha256 calculado, bytes) de cada archivo del lote, sin el manifiesto.
    entradas: list[tuple[str, str, int]] = field(default_factory=list)
    # JSON de cada toma, ya validado.
    tomas: list[dict] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.problemas

    @property
    def prefijo_de_confirmacion(self) -> str | None:
        return self.hash_global[:8] if self.hash_global else None


def _nombre_seguro(nombre: str) -> str | None:
    """Motivo por el que el nombre no es seguro, o None si lo es."""
    if not nombre:
        return "nombre vacio"
    if "/" in nombre or "\\" in nombre:
        return "lleva una barra: un lote es plano, sin carpetas"
    if nombre in (".", "..") or ".." in nombre:
        return "lleva '..'"
    if ":" in nombre:
        return "lleva ':'"
    if nombre.startswith(".") or nombre != nombre.strip():
        return "empieza con punto o tiene espacios en los bordes"
    if not nombre.isascii():
        return "no es ASCII"
    if nombre == NOMBRE_MANIFIESTO:
        return None
    coincide = NOMBRE_ARCHIVO.fullmatch(nombre)
    if not coincide:
        return "no sigue la convencion de nombres (P3_LEDC_D2_R1_G_foto.jpg, ...)"
    base = coincide["base"]
    # Solo R1 lleva tarjeta gris (G); R2 y R3 no (N).
    if base[-1] != ("G" if base.split("_")[3] == "R1" else "N"):
        return "la marca de tarjeta (G o N) no corresponde a la repeticion: solo R1 lleva G"
    return None


def _magia_valida(nombre: str, cabecera: bytes) -> bool:
    """Comprobacion barata de que el contenido es de la clase que dice el nombre."""
    if nombre.endswith("_recorte.png"):
        return cabecera.startswith(b"\x89PNG\r\n\x1a\n")
    if nombre.endswith("_foto.jpg"):
        return cabecera.startswith(b"\xff\xd8\xff")
    if nombre.endswith("_foto.heic"):
        return cabecera[4:8] == b"ftyp"
    return True


def verificar_lote(
    ruta_zip: Path,
    max_archivos: int = MAX_ARCHIVOS,
    max_bytes: int = MAX_BYTES,
) -> Resultado:
    """Comprueba el zip entero sin escribir nada. Junta todos los problemas."""
    r = Resultado()
    try:
        zf = zipfile.ZipFile(ruta_zip)
    except ERRORES_DE_ZIP as e:
        r.problemas.append(f"no se puede abrir como zip: {e}")
        return r

    with zf:
        infos = zf.infolist()
        if len(infos) > max_archivos:
            r.problemas.append(f"demasiados archivos ({len(infos)}; el tope es {max_archivos})")
            return r
        declarado = sum(i.file_size for i in infos)
        if declarado > max_bytes:
            r.problemas.append(f"el zip declara {declarado} bytes; el tope es {max_bytes}")
            return r

        nombres: list[str] = []
        vistos: set[str] = set()
        for info in infos:
            n = info.filename
            motivo = "es una carpeta" if info.is_dir() else _nombre_seguro(n)
            if motivo:
                r.problemas.append(f"entrada '{n}': {motivo}")
                continue
            if n in vistos:
                r.problemas.append(f"entrada repetida: '{n}'")
                continue
            if info.flag_bits & 0x1:
                r.problemas.append(f"entrada '{n}': esta cifrada")
                continue
            vistos.add(n)
            nombres.append(n)
        if r.problemas:
            return r  # con nombres peligrosos no se lee nada mas

        if NOMBRE_MANIFIESTO not in vistos:
            r.problemas.append(f"falta {NOMBRE_MANIFIESTO}")
            return r

        manifiesto = _leer_manifiesto(zf, r)
        calculados: dict[str, tuple[str, int]] = {}
        cabeceras: dict[str, bytes] = {}
        for n in sorted(nombres):
            if n == NOMBRE_MANIFIESTO:
                continue
            info = zf.getinfo(n)
            try:
                sha, total, cabecera = _hash_de_entrada(zf, info)
            except ERRORES_DE_ZIP as e:
                r.problemas.append(f"'{n}': no se pudo leer ({e})")
                continue
            calculados[n] = (sha, total)
            cabeceras[n] = cabecera

        r.entradas = [(n, sha, total) for n, (sha, total) in sorted(calculados.items())]
        if manifiesto is not None:
            _comparar_con_manifiesto(r, manifiesto, calculados)
        r.hash_global = calcular_hash_global([(n, sha) for n, sha, _ in r.entradas])

        for n, cabecera in cabeceras.items():
            if not _magia_valida(n, cabecera):
                r.problemas.append(f"'{n}': su contenido no es de la clase que indica el nombre")

        _verificar_tomas(zf, r, calculados)
    return r


def _hash_de_entrada(zf: zipfile.ZipFile, info: zipfile.ZipInfo) -> tuple[str, int, bytes]:
    h = hashlib.sha256()
    total = 0
    cabecera = b""
    with zf.open(info) as f:
        while True:
            bloque = f.read(BLOQUE)
            if not bloque:
                break
            if not cabecera:
                cabecera = bloque[:16]
            total += len(bloque)
            if total > info.file_size:
                raise zipfile.BadZipFile("tiene mas bytes de los que declara")
            h.update(bloque)
    if total != info.file_size:
        raise zipfile.BadZipFile("tiene menos bytes de los que declara")
    return h.hexdigest(), total, cabecera


def _leer_json(zf: zipfile.ZipFile, nombre: str, r: Resultado) -> object | None:
    info = zf.getinfo(nombre)
    if info.file_size > MAX_BYTES_JSON:
        r.problemas.append(f"'{nombre}': es demasiado grande para ser un JSON de metadatos")
        return None
    try:
        with zf.open(info) as f:
            return json.loads(f.read().decode("utf-8"))
    except ERRORES_DE_ZIP as e:
        r.problemas.append(f"'{nombre}': no es un JSON valido ({e})")
        return None


def validar_estructura_manifiesto(m: object) -> list[str]:
    """Problemas de forma de un manifiesto.json (esquema 1). Vacio si es valido.

    Es el espejo de `Manifiesto.toJson` en la app (lote.dart). Solo comprueba la
    forma; que los hashes correspondan a los archivos se comprueba aparte.
    """
    if not isinstance(m, dict):
        return ["manifiesto: no es un objeto JSON"]
    p: list[str] = []
    _claves(p, "manifiesto", m, {"esquema", "archivos", "hash_global"})
    if not _es_entero(m.get("esquema")) or m.get("esquema") != ESQUEMA_MANIFIESTO:
        p.append(f"manifiesto: esquema debe ser {ESQUEMA_MANIFIESTO}")
    if not isinstance(m.get("hash_global"), str) or not SHA256.fullmatch(m.get("hash_global", "")):
        p.append("manifiesto: hash_global debe ser un SHA-256 en hexadecimal minuscula")
    archivos = m.get("archivos")
    if not isinstance(archivos, list):
        p.append("manifiesto: archivos debe ser una lista")
        return p
    rutas: set[str] = set()
    for i, e in enumerate(archivos):
        if not isinstance(e, dict):
            p.append(f"manifiesto: archivos[{i}] debe ser un objeto")
            continue
        _claves(p, f"manifiesto.archivos[{i}]", e, {"ruta", "sha256", "bytes"})
        if not isinstance(e.get("ruta"), str):
            p.append(f"manifiesto.archivos[{i}].ruta debe ser un texto")
        elif e["ruta"] in rutas:
            p.append(f"manifiesto: ruta repetida '{e['ruta']}'")
        else:
            rutas.add(e["ruta"])
        if not isinstance(e.get("sha256"), str) or not SHA256.fullmatch(e.get("sha256", "")):
            p.append(f"manifiesto.archivos[{i}].sha256 no es un SHA-256")
        if not _es_entero(e.get("bytes")) or e.get("bytes") < 0:
            p.append(f"manifiesto.archivos[{i}].bytes debe ser un entero mayor o igual a 0")
    return p


def _leer_manifiesto(zf: zipfile.ZipFile, r: Resultado) -> dict | None:
    m = _leer_json(zf, NOMBRE_MANIFIESTO, r)
    if m is None:
        return None
    problemas = validar_estructura_manifiesto(m)
    if problemas:
        r.problemas.extend(problemas)
        return None
    return m


def _comparar_con_manifiesto(
    r: Resultado, m: dict, calculados: dict[str, tuple[str, int]]
) -> None:
    declarados = {e["ruta"]: e for e in m["archivos"]}
    for n in sorted(declarados.keys() - calculados.keys()):
        r.problemas.append(f"el manifiesto lista '{n}' pero no esta en el zip")
    for n in sorted(calculados.keys() - declarados.keys()):
        r.problemas.append(f"'{n}' esta en el zip pero no en el manifiesto")
    for n in sorted(declarados.keys() & calculados.keys()):
        sha, total = calculados[n]
        if declarados[n]["sha256"] != sha:
            r.problemas.append(f"'{n}': el SHA-256 no coincide con el del manifiesto")
        if declarados[n]["bytes"] != total:
            r.problemas.append(f"'{n}': el tamano no coincide con el del manifiesto")
    esperado = calcular_hash_global([(e["ruta"], e["sha256"]) for e in m["archivos"]])
    if m["hash_global"] != esperado:
        r.problemas.append("el hash global del manifiesto no corresponde a su lista de archivos")


def _verificar_tomas(
    zf: zipfile.ZipFile, r: Resultado, calculados: dict[str, tuple[str, int]]
) -> None:
    """Cada JSON valida, y cada JSON y sus dos archivos se corresponden."""
    por_base: dict[str, dict[str, str]] = {}
    for n in calculados:
        coincide = NOMBRE_ARCHIVO.fullmatch(n)
        if not coincide:
            continue
        resto = coincide["resto"]
        clase = "json" if resto == ".json" else ("recorte" if resto.endswith(".png") else "foto")
        por_base.setdefault(coincide["base"], {})[clase] = n

    for base in sorted(por_base):
        piezas = por_base[base]
        for clase in ("json", "foto", "recorte"):
            if clase not in piezas:
                r.problemas.append(f"toma {base}: falta el archivo de tipo {clase}")
        if "json" not in piezas:
            continue
        contenido = _leer_json(zf, piezas["json"], r)
        if contenido is None:
            continue
        problemas = validar_metadatos(contenido)
        for pr in problemas:
            r.problemas.append(f"{piezas['json']}: {pr}")
        if problemas:
            continue
        archivos = contenido["archivos"]
        if f"{contenido['seudonimo']}_{contenido['luz']}_{contenido['celular']['codigo']}_" \
           f"{contenido['repeticion']}_{'G' if contenido['repeticion'] == 'R1' else 'N'}" != base:
            r.problemas.append(f"{piezas['json']}: el contenido no corresponde al nombre del archivo")
            continue
        for clase in ("foto", "recorte"):
            nombre = archivos[clase]
            if nombre != piezas.get(clase):
                r.problemas.append(f"{piezas['json']}: declara {nombre} pero el zip trae {piezas.get(clase)}")
            elif calculados[nombre][0] != archivos["sha256"][clase]:
                r.problemas.append(f"{piezas['json']}: el SHA-256 de {nombre} no coincide con el declarado")
        r.tomas.append(contenido)


# --------------------------------------------------------------------------- #
# Resumen
# --------------------------------------------------------------------------- #


def resumir(r: Resultado) -> str:
    """Texto de resumen: tomas por persona, por celular y por luz."""
    tomas = r.tomas
    lineas = [
        f"Tomas: {len(tomas)}   Archivos: {len(r.entradas)}   "
        f"Bytes: {sum(b for _, _, b in r.entradas):,}",
    ]
    for titulo, clave, orden in (
        ("Por persona", lambda t: t["seudonimo"], sorted({t["seudonimo"] for t in tomas})),
        ("Por celular", lambda t: t["celular"]["codigo"], sorted({t["celular"]["codigo"] for t in tomas})),
        ("Por luz", lambda t: t["luz"], [x for x in LUCES if any(t["luz"] == x for t in tomas)]),
    ):
        cuentas = ", ".join(f"{k}: {sum(1 for t in tomas if clave(t) == k)}" for k in orden)
        lineas.append(f"{titulo}: {cuentas or '-'}")
    combos = sorted({(t["seudonimo"], t["celular"]["codigo"]) for t in tomas})
    if combos:
        lineas.append("Avance por persona y celular (15 tomas cada uno):")
        for s, c in combos:
            n = sum(1 for t in tomas if t["seudonimo"] == s and t["celular"]["codigo"] == c)
            lineas.append(f"  {s} / {c}: {n}/15")
    return "\n".join(lineas)


# --------------------------------------------------------------------------- #
# Copia a la boveda
# --------------------------------------------------------------------------- #


def esta_en_un_repositorio(ruta: Path) -> Path | None:
    """El repositorio que contiene a `ruta` (la carpeta con .git), o None."""
    actual = ruta.resolve()
    while True:
        if (actual / ".git").exists():
            return actual
        if actual.parent == actual:
            return None
        actual = actual.parent


def ruta_de_configuracion_por_defecto() -> Path:
    env = os.environ.get("WEARHACK_IMPORTAR_LOTE_CONFIG")
    if env:
        return Path(env)
    try:
        return Path.home() / ".wearhack" / "importar_lote.json"
    except RuntimeError as e:
        raise ErrorDeConfiguracion(
            "No se puede determinar el directorio personal. Usa --config o la variable "
            "de entorno WEARHACK_IMPORTAR_LOTE_CONFIG."
        ) from e


def cargar_boveda(ruta_config: Path) -> Path:
    """Lee la ruta de la boveda del archivo de configuracion.

    Lanza ErrorDeConfiguracion si el archivo falta, esta mal, o si el archivo o
    la boveda estan dentro de un repositorio.
    """
    if not ruta_config.is_file():
        raise ErrorDeConfiguracion(
            f"No existe la configuracion en {ruta_config}.\n"
            'Crea un archivo JSON fuera del repositorio con: {"boveda": "<ruta de la boveda montada>"}'
        )
    repo = esta_en_un_repositorio(ruta_config)
    if repo is not None:
        raise ErrorDeConfiguracion(
            f"La configuracion {ruta_config} esta dentro del repositorio {repo}. "
            "Debe vivir fuera de el."
        )
    try:
        datos = json.loads(ruta_config.read_text(encoding="utf-8"))
    except (ValueError, OSError) as e:
        raise ErrorDeConfiguracion(f"No se pudo leer {ruta_config}: {e}") from e
    if not isinstance(datos, dict) or set(datos) != {"boveda"} or not isinstance(datos["boveda"], str):
        raise ErrorDeConfiguracion(f'{ruta_config} debe ser exactamente {{"boveda": "<ruta>"}}')
    boveda = Path(datos["boveda"])
    if not boveda.is_dir():
        raise ErrorDeConfiguracion(
            f"La boveda {boveda} no existe o no es una carpeta. Esta montada Cryptomator?"
        )
    repo = esta_en_un_repositorio(boveda)
    if repo is not None:
        raise ErrorDeConfiguracion(
            f"La boveda {boveda} esta dentro del repositorio {repo}. Las fotos de "
            "calibracion nunca van en un repositorio."
        )
    return boveda.resolve()


def resolver_destino(boveda: Path, destino: str) -> Path:
    """Carpeta de destino dentro de la boveda. Rechaza lo que se salga de ella."""
    partes = destino.replace("\\", "/").split("/")
    if not destino or any(not COMPONENTE_DE_RUTA.fullmatch(p) or p.startswith("..") for p in partes):
        raise ErrorDeConfiguracion(
            f"Destino invalido '{destino}': solo letras, numeros, punto, guion y guion bajo, "
            "sin '..' ni rutas absolutas."
        )
    final = (boveda / Path(*partes)).resolve()
    if not final.is_relative_to(boveda):
        raise ErrorDeConfiguracion(f"El destino '{destino}' se sale de la boveda")
    return final


def copiar_lote(ruta_zip: Path, resultado: Resultado, destino: Path) -> Path:
    """Copia el lote verificado a `destino` sin sobrescribir y sin dejar nada a medias.

    Copia a una carpeta temporal hermana, vuelve a leer lo copiado para comprobar
    su SHA-256, y renombra al final. Lanza ErrorDeCopia si algo falla.
    """
    if not resultado.ok:
        raise ErrorDeCopia("El lote no paso la verificacion; no se copia")
    if destino.exists():
        raise ErrorDeCopia(f"El destino {destino} ya existe; no se sobrescribe")
    temporal = destino.parent / f".{destino.name}.importando"
    if temporal.exists():
        raise ErrorDeCopia(
            f"Queda una importacion a medias en {temporal}. Revisala y borrala a mano."
        )
    esperado = {n: (sha, total) for n, sha, total in resultado.entradas}

    destino.parent.mkdir(parents=True, exist_ok=True)
    temporal.mkdir()
    try:
        with zipfile.ZipFile(ruta_zip) as zf:
            for n in sorted(list(esperado) + [NOMBRE_MANIFIESTO]):
                _copiar_entrada(zf, n, temporal / n, esperado.get(n))
        for n, (sha, _) in esperado.items():
            h = hashlib.sha256((temporal / n).read_bytes()).hexdigest()
            if h != sha:
                raise ErrorDeCopia(f"'{n}' no coincide con su SHA-256 despues de copiarlo")
        if sorted(p.name for p in temporal.iterdir()) != sorted(list(esperado) + [NOMBRE_MANIFIESTO]):
            raise ErrorDeCopia("La carpeta copiada no tiene los archivos esperados")
        temporal.rename(destino)
    except BaseException as e:
        shutil.rmtree(temporal, ignore_errors=True)
        if isinstance(e, ErrorDeCopia):
            raise
        if isinstance(e, ERRORES_DE_ZIP):
            raise ErrorDeCopia(f"Fallo la copia: {e}") from e
        raise
    return destino


def _copiar_entrada(
    zf: zipfile.ZipFile, nombre: str, destino: Path, esperado: tuple[str, int] | None
) -> None:
    h = hashlib.sha256()
    with zf.open(nombre) as origen, open(destino, "xb") as salida:
        while True:
            bloque = origen.read(BLOQUE)
            if not bloque:
                break
            h.update(bloque)
            salida.write(bloque)
        salida.flush()
        os.fsync(salida.fileno())
    if esperado is not None and h.hexdigest() != esperado[0]:
        raise ErrorDeCopia(f"'{nombre}' cambio entre la verificacion y la copia")


# --------------------------------------------------------------------------- #
# Linea de comandos
# --------------------------------------------------------------------------- #


def construir_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="importar_lote.py",
        description="Verifica un lote de tomas de calibracion y lo copia a la boveda Cryptomator.",
    )
    p.add_argument("zip", type=Path, help="el .zip exportado por la app")
    p.add_argument(
        "--destino",
        help="carpeta dentro de la boveda (por defecto, el nombre del zip sin extension)",
    )
    p.add_argument(
        "--config", type=Path,
        help="archivo de configuracion (por defecto $WEARHACK_IMPORTAR_LOTE_CONFIG o ~/.wearhack/importar_lote.json)",
    )
    p.add_argument(
        "--solo-verificar", action="store_true",
        help="comprueba el lote y muestra el hash, sin copiar nada ni leer la configuracion",
    )
    return p


def principal(argv: list[str] | None = None, salida=None) -> int:
    salida = salida or sys.stdout
    imprimir = lambda *a: print(*a, file=salida)  # noqa: E731
    args = construir_parser().parse_args(argv)

    if not args.zip.is_file():
        imprimir(f"No existe el archivo {args.zip}")
        return 2

    destino = None
    if not args.solo_verificar:
        try:
            boveda = cargar_boveda(args.config or ruta_de_configuracion_por_defecto())
            destino = resolver_destino(boveda, args.destino or args.zip.stem)
        except ErrorDeConfiguracion as e:
            imprimir(f"ERROR de configuracion: {e}")
            return 2

    r = verificar_lote(args.zip)
    if not r.ok:
        imprimir(f"EL LOTE NO PASA LA VERIFICACION ({len(r.problemas)} problemas). No se copio nada.")
        for pr in r.problemas:
            imprimir(f"  - {pr}")
        return 1

    imprimir(resumir(r))
    if not args.solo_verificar:
        try:
            final = copiar_lote(args.zip, r, destino)
        except ErrorDeCopia as e:
            imprimir(f"ERROR: {e}. No se copio nada.")
            return 1
        imprimir(f"Copiado a {final}")
    else:
        imprimir("Solo verificacion: no se copio nada.")

    imprimir("")
    imprimir(f"Hash global: {r.hash_global}")
    imprimir(f"Para habilitar Borrar en la app, escribe: {r.prefijo_de_confirmacion}")
    return 0


if __name__ == "__main__":
    sys.exit(principal())
