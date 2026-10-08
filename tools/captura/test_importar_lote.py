"""Pruebas de importar_lote.py.

Se corren con la libreria estandar, sin instalar nada:

    python -m unittest discover -s tools/captura -v

Todo es sintetico y vive en el directorio temporal del sistema: ninguna foto de
calibracion, ni parecida, entra al repositorio. Los "archivos de foto" son bytes
con la cabecera correcta y relleno determinista.
"""

from __future__ import annotations

import copy
import hashlib
import io
import json
import tempfile
import unittest
import warnings
import zipfile
from pathlib import Path
from unittest import mock

import importar_lote as il

EJEMPLOS = Path(__file__).parent / "ejemplos"

# El mismo vector, y el mismo resultado, estan en paridad_con_python_test.dart.
VECTOR_ENTRADAS = [("B.jpg", "1" * 64), ("a.jpg", "2" * 64), ("P3_LEDC_D2_R1_G.json", "c" * 64)]
VECTOR_HASH = "0e11c978905cd7059f7caa36b1469fb8d1a1bad5394a122c585eba3033c5bd42"


def _relleno(clave: str, n: int = 300) -> bytes:
    return hashlib.sha256(clave.encode()).digest() * (n // 32 + 1)


def _jpg(clave: str) -> bytes:
    return b"\xff\xd8\xff\xe0" + _relleno(clave)


def _png(clave: str) -> bytes:
    return b"\x89PNG\r\n\x1a\n" + _relleno(clave)


def _sha(datos: bytes) -> str:
    return hashlib.sha256(datos).hexdigest()


def nombre_base(seudonimo="P3", luz="LEDC", celular="D2", rep="R1") -> str:
    return f"{seudonimo}_{luz}_{celular}_{rep}_{'G' if rep == 'R1' else 'N'}"


def metadatos(seudonimo="P3", luz="LEDC", celular="D2", rep="R1", sha_foto="a" * 64, sha_recorte="b" * 64) -> dict:
    base = nombre_base(seudonimo, luz, celular, rep)
    return {
        "esquema": 1,
        "seudonimo": seudonimo,
        "luz": luz,
        "repeticion": rep,
        "tarjeta_gris": rep == "R1",
        "fecha_hora": "2026-10-15T15:42:07-05:00",
        "celular": {"codigo": celular, "modelo": "Modelo de prueba", "sistema": "Android 14", "build_app": "0.1.0+1"},
        "pantalla": {"true_tone_o_night_shift": False},
        "camara": {"lente": "frontal", "flash": "apagado",
                   "parametros": {"exposicion": None, "iso": None, "balance_blancos": None}},
        "rostro": {"bbox": [100, 100, 250, 270], "ancho_px": 150},
        "perfil_color": {"foto": "Display P3", "recorte": "sRGB (convertido por la app)"},
        "archivos": {"foto": f"{base}_foto.jpg", "recorte": f"{base}_recorte.png",
                     "sha256": {"foto": sha_foto, "recorte": sha_recorte}},
    }


def _json_bytes(obj) -> bytes:
    return (json.dumps(obj, indent=2) + "\n").encode()


def archivos_de_toma(seudonimo="P3", luz="LEDC", celular="D2", rep="R1", alterar=None) -> dict[str, bytes]:
    base = nombre_base(seudonimo, luz, celular, rep)
    foto, recorte = _jpg(base + "foto"), _png(base + "recorte")
    meta = metadatos(seudonimo, luz, celular, rep, _sha(foto), _sha(recorte))
    if alterar:
        alterar(meta)
    return {f"{base}_foto.jpg": foto, f"{base}_recorte.png": recorte, f"{base}.json": _json_bytes(meta)}


def manifiesto_de(archivos: dict[str, bytes]) -> dict:
    """Manifiesto calculado SIN usar el codigo bajo prueba."""
    entradas = [{"ruta": n, "sha256": _sha(d), "bytes": len(d)} for n, d in sorted(archivos.items())]
    texto = "".join(f"{e['sha256']}  {e['ruta']}\n" for e in sorted(entradas, key=lambda e: e["ruta"]))
    return {"esquema": 1, "archivos": entradas, "hash_global": hashlib.sha256(texto.encode()).hexdigest()}


def escribir_zip(ruta: Path, archivos: dict[str, bytes], manifiesto: dict | bytes | None, extras=()) -> Path:
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")  # nombres repetidos a proposito
        with zipfile.ZipFile(ruta, "w", zipfile.ZIP_STORED) as z:
            for n, d in archivos.items():
                z.writestr(n, d)
            for n, d in extras:
                z.writestr(n, d)
            if manifiesto is not None:
                z.writestr(il.NOMBRE_MANIFIESTO, manifiesto if isinstance(manifiesto, bytes) else _json_bytes(manifiesto))
    return ruta


class Lote:
    """Un lote de prueba con el que se puede estropear una pieza a la vez."""

    TOMAS = [("P3", "LEDC", "D2", "R1"), ("P3", "LEDC", "D2", "R2"), ("P3", "VEN", "D2", "R1")]

    def __init__(self, carpeta: Path, nombre="lote.zip"):
        self.carpeta = carpeta
        self.nombre = nombre
        self.archivos: dict[str, bytes] = {}
        for t in self.TOMAS:
            self.archivos.update(archivos_de_toma(*t))
        self.manifiesto = manifiesto_de(self.archivos)

    def zip(self, manifiesto="auto", extras=()) -> Path:
        m = self.manifiesto if manifiesto == "auto" else manifiesto
        return escribir_zip(self.carpeta / self.nombre, self.archivos, m, extras)


class Base(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory(prefix="wearhack_import_")
        self.addCleanup(self._tmp.cleanup)
        self.dir = Path(self._tmp.name)
        self.lote = Lote(self.dir)

    def problemas(self, zip_path: Path, **kw) -> str:
        r = il.verificar_lote(zip_path, **kw)
        self.assertFalse(r.ok, "debia fallar la verificacion")
        return " | ".join(r.problemas)


class HashGlobalYFormato(unittest.TestCase):
    def test_vector_compartido_con_la_app(self):
        self.assertEqual(il.calcular_hash_global(VECTOR_ENTRADAS), VECTOR_HASH)

    def test_no_depende_del_orden_de_entrada(self):
        self.assertEqual(il.calcular_hash_global(VECTOR_ENTRADAS[::-1]), VECTOR_HASH)

    def test_el_orden_es_ordinal_no_el_del_idioma(self):
        # "B" (66) va antes que "a" (97).
        texto = f"{'1' * 64}  B.jpg\n{'2' * 64}  a.jpg\n"
        self.assertEqual(il.calcular_hash_global([("a.jpg", "2" * 64), ("B.jpg", "1" * 64)]),
                         hashlib.sha256(texto.encode()).hexdigest())

    def test_metadatos_de_referencia_generados_por_la_app(self):
        datos = json.loads((EJEMPLOS / "metadatos_ejemplo.json").read_text(encoding="utf-8"))
        self.assertEqual(il.validar_metadatos(datos), [])

    def test_manifiesto_de_referencia_generado_por_la_app(self):
        datos = json.loads((EJEMPLOS / "manifiesto_ejemplo.json").read_text(encoding="utf-8"))
        self.assertEqual(il.validar_estructura_manifiesto(datos), [])
        recalculado = il.calcular_hash_global([(e["ruta"], e["sha256"]) for e in datos["archivos"]])
        self.assertEqual(datos["hash_global"], recalculado)

    def test_los_dos_ejemplos_son_coherentes_entre_si(self):
        meta = json.loads((EJEMPLOS / "metadatos_ejemplo.json").read_text(encoding="utf-8"))
        man = json.loads((EJEMPLOS / "manifiesto_ejemplo.json").read_text(encoding="utf-8"))
        por_ruta = {e["ruta"]: e for e in man["archivos"]}
        self.assertEqual(por_ruta[meta["archivos"]["foto"]]["sha256"], meta["archivos"]["sha256"]["foto"])
        self.assertEqual(por_ruta[meta["archivos"]["recorte"]]["sha256"], meta["archivos"]["sha256"]["recorte"])


class EsquemaDeMetadatos(unittest.TestCase):
    def test_uno_valido(self):
        self.assertEqual(il.validar_metadatos(metadatos()), [])

    def test_los_codigos_son_los_de_la_app(self):
        self.assertEqual(il.LUCES, ("VEN", "LEDC", "LEDF", "MIX", "BAJ"))
        self.assertEqual(il.CELULARES, ("D1", "D2", "D3"))
        self.assertEqual(il.REPETICIONES, ("R1", "R2", "R3"))

    CASOS = [
        ("falta una clave", lambda j: j.pop("luz"), 'falta la clave "luz"'),
        ("clave de mas", lambda j: j.update(extra=1), 'clave no prevista "extra"'),
        ("esquema distinto", lambda j: j.update(esquema=2), "esquema debe ser 1"),
        ("esquema booleano", lambda j: j.update(esquema=True), "esquema debe ser 1"),
        ("seudonimo invalido", lambda j: j.update(seudonimo="P9"), "seudonimo"),
        ("seudonimo con salto de linea", lambda j: j.update(seudonimo="P1\n"), "seudonimo"),
        ("luz invalida", lambda j: j.update(luz="SOL"), "luz no es"),
        ("repeticion invalida", lambda j: j.update(repeticion="R9"), "repeticion no es"),
        ("tarjeta no corresponde", lambda j: j.update(tarjeta_gris=False), "tarjeta_gris no corresponde"),
        ("tarjeta no booleana", lambda j: j.update(tarjeta_gris=1), "tarjeta_gris debe ser booleano"),
        ("fecha sin desfase", lambda j: j.update(fecha_hora="2026-10-15T15:42:07"), "fecha_hora"),
        ("fecha con salto de linea", lambda j: j.update(fecha_hora="2026-10-15T15:42:07-05:00\n"), "fecha_hora"),
        ("celular invalido", lambda j: j["celular"].update(codigo="D9"), "celular.codigo"),
        ("modelo vacio", lambda j: j["celular"].update(modelo=""), "celular.modelo"),
        ("true tone no booleano", lambda j: j["pantalla"].update(true_tone_o_night_shift="si"), "true_tone"),
        ("lente trasera", lambda j: j["camara"].update(lente="trasera"), "camara.lente"),
        ("flash encendido", lambda j: j["camara"].update(flash="encendido"), "camara.flash"),
        ("iso como texto", lambda j: j["camara"]["parametros"].update(iso="alto"), "iso"),
        ("iso booleano", lambda j: j["camara"]["parametros"].update(iso=True), "iso"),
        ("bbox corta", lambda j: j["rostro"].update(bbox=[1, 2, 3]), "bbox"),
        ("bbox con texto", lambda j: j["rostro"].update(bbox=[1, 2, 3, "x"]), "bbox"),
        ("ancho negativo", lambda j: j["rostro"].update(ancho_px=-1), "ancho_px"),
        ("ancho booleano", lambda j: j["rostro"].update(ancho_px=True), "ancho_px"),
        ("perfil de foto vacio", lambda j: j["perfil_color"].update(foto=""), "perfil_color.foto"),
        ("foto con otro nombre", lambda j: j["archivos"].update(foto="otra.jpg"), "archivos.foto"),
        ("recorte con otro nombre", lambda j: j["archivos"].update(recorte="otro.png"), "archivos.recorte"),
        ("sha corto", lambda j: j["archivos"]["sha256"].update(foto="abc"), "sha256.foto"),
        ("sha en mayusculas", lambda j: j["archivos"]["sha256"].update(recorte="A" * 64), "sha256.recorte"),
    ]

    def test_cada_error_se_detecta(self):
        for nombre, mutar, esperado in self.CASOS:
            with self.subTest(nombre):
                j = metadatos()
                mutar(j)
                self.assertIn(esperado, " | ".join(il.validar_metadatos(j)))

    def test_heic_es_valido_y_png_no(self):
        j = metadatos()
        j["archivos"]["foto"] = "P3_LEDC_D2_R1_G_foto.heic"
        self.assertEqual(il.validar_metadatos(j), [])
        j["archivos"]["foto"] = "P3_LEDC_D2_R1_G_foto.png"
        self.assertNotEqual(il.validar_metadatos(j), [])

    def test_lo_que_no_es_un_objeto(self):
        for malo in ([1, 2], "texto", None, 5):
            with self.subTest(malo):
                self.assertNotEqual(il.validar_metadatos(malo), [])

    def test_estructura_del_manifiesto(self):
        bueno = manifiesto_de(archivos_de_toma())
        self.assertEqual(il.validar_estructura_manifiesto(bueno), [])
        casos = [
            ("no objeto", [], "no es un objeto"),
            ("esquema 2", {**bueno, "esquema": 2}, "esquema"),
            ("hash corto", {**bueno, "hash_global": "abc"}, "hash_global"),
            ("sin archivos", {k: v for k, v in bueno.items() if k != "archivos"}, 'falta la clave "archivos"'),
            ("archivos no lista", {**bueno, "archivos": {}}, "lista"),
            ("ruta repetida", {**bueno, "archivos": bueno["archivos"] + [bueno["archivos"][0]]}, "repetida"),
            ("bytes negativo", {**bueno, "archivos": [{**bueno["archivos"][0], "bytes": -1}]}, "bytes"),
            ("bytes booleano", {**bueno, "archivos": [{**bueno["archivos"][0], "bytes": True}]}, "bytes"),
            ("clave de mas", {**bueno, "extra": 1}, "no prevista"),
        ]
        for nombre, m, esperado in casos:
            with self.subTest(nombre):
                self.assertIn(esperado, " | ".join(il.validar_estructura_manifiesto(m)))


class VerificarLote(Base):
    def test_un_lote_sano_pasa(self):
        r = il.verificar_lote(self.lote.zip())

        self.assertTrue(r.ok, r.problemas)
        self.assertEqual(len(r.tomas), 3)
        self.assertEqual(len(r.entradas), 9)

    def test_el_hash_global_coincide_con_el_calculado_aparte(self):
        r = il.verificar_lote(self.lote.zip())

        self.assertEqual(r.hash_global, self.lote.manifiesto["hash_global"])
        self.assertEqual(r.prefijo_de_confirmacion, self.lote.manifiesto["hash_global"][:8])

    def test_el_resumen_cuenta_por_persona_celular_y_luz(self):
        texto = il.resumir(il.verificar_lote(self.lote.zip()))

        self.assertIn("Tomas: 3", texto)
        self.assertIn("P3: 3", texto)
        self.assertIn("D2: 3", texto)
        self.assertIn("LEDC: 2", texto)
        self.assertIn("VEN: 1", texto)
        self.assertIn("P3 / D2: 3/15", texto)

    def test_no_es_un_zip(self):
        ruta = self.dir / "falso.zip"
        ruta.write_bytes(b"esto no es un zip" * 10)

        self.assertIn("no se puede abrir como zip", self.problemas(ruta))

    def test_un_byte_cambiado_en_la_foto(self):
        malo = dict(self.lote.archivos)
        nombre = "P3_LEDC_D2_R1_G_foto.jpg"
        malo[nombre] = malo[nombre][:50] + b"\x00" + malo[nombre][51:]
        ruta = escribir_zip(self.dir / "x.zip", malo, self.lote.manifiesto)

        self.assertIn(f"'{nombre}': el SHA-256 no coincide", self.problemas(ruta))

    def test_un_archivo_que_falta(self):
        malo = dict(self.lote.archivos)
        del malo["P3_LEDC_D2_R1_G_recorte.png"]
        ruta = escribir_zip(self.dir / "x.zip", malo, self.lote.manifiesto)

        self.assertIn("el manifiesto lista 'P3_LEDC_D2_R1_G_recorte.png' pero no esta en el zip", self.problemas(ruta))

    def test_un_archivo_de_mas(self):
        ruta = self.lote.zip(extras=[("P1_BAJ_D1_R2_N_foto.jpg", _jpg("extra"))])

        self.assertIn("esta en el zip pero no en el manifiesto", self.problemas(ruta))

    def test_sin_manifiesto(self):
        self.assertIn("falta manifiesto.json", self.problemas(self.lote.zip(manifiesto=None)))

    def test_manifiesto_que_no_es_json(self):
        self.assertIn("no es un JSON valido", self.problemas(self.lote.zip(manifiesto=b"{ no json")))

    def test_hash_global_alterado(self):
        m = copy.deepcopy(self.lote.manifiesto)
        m["hash_global"] = "0" * 64

        self.assertIn("hash global del manifiesto no corresponde", self.problemas(self.lote.zip(manifiesto=m)))

    def test_hash_global_valido_pero_de_otra_lista(self):
        m = copy.deepcopy(self.lote.manifiesto)
        m["archivos"][0]["sha256"] = "d" * 64

        texto = self.problemas(self.lote.zip(manifiesto=m))

        self.assertIn("no coincide con el del manifiesto", texto)
        self.assertIn("hash global del manifiesto no corresponde", texto)

    def test_tamano_distinto_en_el_manifiesto(self):
        m = copy.deepcopy(self.lote.manifiesto)
        m["archivos"][0]["bytes"] += 1

        self.assertIn("el tamano no coincide", self.problemas(self.lote.zip(manifiesto=m)))

    def test_manifiesto_con_esquema_2(self):
        m = {**self.lote.manifiesto, "esquema": 2}

        self.assertIn("esquema", self.problemas(self.lote.zip(manifiesto=m)))

    def test_json_de_toma_invalido_aunque_el_manifiesto_sea_coherente(self):
        # El caso peligroso: el manifiesto cuadra con unos archivos que estan mal.
        malos = dict(self.lote.archivos)
        malos.update(archivos_de_toma("P3", "LEDC", "D2", "R1", alterar=lambda j: j.update(luz="SOL")))
        ruta = escribir_zip(self.dir / "x.zip", malos, manifiesto_de(malos))

        self.assertIn("luz no es", self.problemas(ruta))

    def test_el_sha_declarado_en_el_json_no_es_el_del_archivo(self):
        malos = dict(self.lote.archivos)
        malos.update(archivos_de_toma("P3", "LEDC", "D2", "R1",
                                      alterar=lambda j: j["archivos"]["sha256"].update(foto="e" * 64)))
        ruta = escribir_zip(self.dir / "x.zip", malos, manifiesto_de(malos))

        self.assertIn("el SHA-256 de P3_LEDC_D2_R1_G_foto.jpg no coincide con el declarado", self.problemas(ruta))

    def test_el_json_dice_otra_persona_que_su_nombre(self):
        # Un JSON completo y coherente de P1 guardado bajo el nombre de P3: solo la
        # comparacion entre contenido y nombre lo puede detectar.
        malos = dict(self.lote.archivos)
        base = nombre_base("P3", "LEDC", "D2", "R1")
        malos[f"{base}.json"] = archivos_de_toma("P1", "LEDC", "D2", "R1")[f"{nombre_base('P1')}.json"]
        ruta = escribir_zip(self.dir / "x.zip", malos, manifiesto_de(malos))

        self.assertIn("el contenido no corresponde al nombre del archivo", self.problemas(ruta))

    def test_el_json_apunta_a_archivos_con_otro_nombre(self):
        # Contenido de P3 coherente consigo mismo, pero el JSON de otra toma de P3.
        malos = dict(self.lote.archivos)
        base = nombre_base("P3", "LEDC", "D2", "R1")
        otro = archivos_de_toma("P3", "LEDC", "D2", "R2")[f"{nombre_base('P3', 'LEDC', 'D2', 'R2')}.json"]
        malos[f"{base}.json"] = otro
        ruta = escribir_zip(self.dir / "x.zip", malos, manifiesto_de(malos))

        self.assertIn("no corresponde al nombre", self.problemas(ruta))

    def test_heic_con_una_cabecera_que_no_es_heic(self):
        base = nombre_base("P2", "BAJ", "D1", "R3")
        foto = b"\x00\x00\x00\x18xxxx" + _relleno("heic")
        recorte = _png("heic-recorte")
        meta = metadatos("P2", "BAJ", "D1", "R3", _sha(foto), _sha(recorte))
        meta["archivos"]["foto"] = f"{base}_foto.heic"
        archivos = {f"{base}_foto.heic": foto, f"{base}_recorte.png": recorte, f"{base}.json": _json_bytes(meta)}
        ruta = escribir_zip(self.dir / "x.zip", archivos, manifiesto_de(archivos))

        self.assertIn("no es de la clase que indica el nombre", self.problemas(ruta))

    def test_foto_huerfana_sin_json(self):
        malos = dict(self.lote.archivos)
        del malos["P3_LEDC_D2_R2_N.json"]
        ruta = escribir_zip(self.dir / "x.zip", malos, manifiesto_de(malos))

        self.assertIn("toma P3_LEDC_D2_R2_N: falta el archivo de tipo json", self.problemas(ruta))

    def test_json_sin_su_foto(self):
        malos = dict(self.lote.archivos)
        del malos["P3_LEDC_D2_R2_N_foto.jpg"]
        ruta = escribir_zip(self.dir / "x.zip", malos, manifiesto_de(malos))

        self.assertIn("falta el archivo de tipo foto", self.problemas(ruta))

    def test_nombres_fuera_de_la_convencion(self):
        for nombre in ("foto.jpg", "P3_LEDC_D2_R1_N_foto.jpg", "P3_LEDC_D2_R2_G_foto.jpg",
                       "P7_LEDC_D2_R1_G_foto.jpg", "P3_LEDC_D2_R1_G_foto.png", "p3_ledc_d2_r1_g.json"):
            with self.subTest(nombre):
                malos = dict(self.lote.archivos)
                malos[nombre] = _jpg("x")
                ruta = escribir_zip(self.dir / "x.zip", malos, manifiesto_de(malos))

                texto = self.problemas(ruta)

                self.assertTrue("no sigue la convencion" in texto or "marca de tarjeta" in texto, texto)

    def test_la_marca_de_tarjeta_debe_corresponder_a_la_repeticion(self):
        for nombre in ("P3_LEDC_D2_R1_N_foto.jpg", "P3_LEDC_D2_R2_G_foto.jpg", "P3_LEDC_D2_R3_G.json"):
            with self.subTest(nombre):
                malos = dict(self.lote.archivos)
                malos[nombre] = _jpg("x")
                ruta = escribir_zip(self.dir / "x.zip", malos, manifiesto_de(malos))

                self.assertIn("marca de tarjeta", self.problemas(ruta))

    def test_una_entrada_cifrada_se_rechaza_sin_leerla(self):
        ruta = self.lote.zip()
        datos = bytearray(ruta.read_bytes())
        nombre = b"P3_LEDC_D2_R1_G_foto.jpg"
        i = datos.index(b"PK")
        while datos[i + 30:i + 30 + len(nombre)] != nombre:
            i = datos.index(b"PK", i + 1)
        datos[i + 6] |= 0x01  # bit 0 de la cabecera local
        j = datos.index(b"PK")
        while datos[j + 46:j + 46 + len(nombre)] != nombre:
            j = datos.index(b"PK", j + 1)
        datos[j + 8] |= 0x01  # y de la central
        ruta.write_bytes(bytes(datos))

        self.assertIn("esta cifrada", self.problemas(ruta))

    # Cada nombre con la razon exacta por la que se rechaza. Pedir la razon, y no
    # solo "entrada", es lo que obliga a que cada comprobacion funcione por si
    # sola: la lista blanca final tambien los rechazaria, pero con otro mensaje.
    NOMBRES_PELIGROSOS = (
        ("../evil.png", "barra"),
        ("/abs/evil.png", "barra"),
        ("C:\\evil.png", "barra"),
        ("a/b.json", "barra"),
        ("a\\b.json", "barra"),
        ("..", "'..'"),
        ("a..b.jpg", "'..'"),
        ("C:evil.png", "':'"),
        ("caf\u00e9.jpg", "no es ASCII"),
        (".oculto", "empieza con punto"),
        (" P3_LEDC_D2_R1_G_foto.jpg", "espacios en los bordes"),
        ("P3_LEDC_D2_R1_G_foto.jpg\n", "espacios en los bordes"),
    )

    def test_nombres_peligrosos_se_rechazan_por_su_razon(self):
        for nombre, razon in self.NOMBRES_PELIGROSOS:
            with self.subTest(repr(nombre)):
                texto = self.problemas(self.lote.zip(extras=[(nombre, b"x")]))

                self.assertIn(razon, texto)

    def test_con_nombres_peligrosos_no_se_lee_ningun_archivo(self):
        ruta = self.lote.zip(extras=[("../evil.png", b"x")])

        with mock.patch.object(il, "_hash_de_entrada", side_effect=AssertionError("se leyo un archivo")):
            r = il.verificar_lote(ruta)

        self.assertFalse(r.ok)
        self.assertEqual(r.entradas, [])

    def test_con_nombres_peligrosos_no_se_pide_ni_el_manifiesto(self):
        ruta = self.lote.zip(manifiesto=None, extras=[("../evil.png", b"x")])

        texto = self.problemas(ruta)

        self.assertNotIn("falta manifiesto.json", texto)

    def test_un_zip_que_declara_mas_bytes_de_los_que_trae(self):
        ruta = self.lote.zip()
        datos = bytearray(ruta.read_bytes())
        nombre = b"P3_LEDC_D2_R1_G_foto.jpg"
        j = datos.index(b"PK\x01\x02")
        while datos[j + 46:j + 46 + len(nombre)] != nombre:
            j = datos.index(b"PK\x01\x02", j + 1)
        tamano = int.from_bytes(datos[j + 24:j + 28], "little")
        datos[j + 24:j + 28] = (tamano + 5).to_bytes(4, "little")  # declara 5 bytes de mas
        ruta.write_bytes(bytes(datos))

        self.assertIn("menos bytes de los que declara", self.problemas(ruta))

    def test_entrada_repetida(self):
        ruta = self.lote.zip(extras=[("P3_LEDC_D2_R1_G_foto.jpg", _jpg("otra"))])

        self.assertIn("entrada repetida", self.problemas(ruta))

    def test_carpeta_dentro_del_zip(self):
        ruta = self.dir / "x.zip"
        with zipfile.ZipFile(ruta, "w") as z:
            z.writestr("carpeta/", b"")
            z.writestr(il.NOMBRE_MANIFIESTO, _json_bytes(self.lote.manifiesto))

        self.assertIn("es una carpeta", self.problemas(ruta))

    def test_contenido_que_no_es_de_la_clase_del_nombre(self):
        for nombre, contenido in (("P3_LEDC_D2_R1_G_foto.jpg", b"no soy un jpeg"),
                                  ("P3_LEDC_D2_R1_G_recorte.png", b"no soy un png"),):
            with self.subTest(nombre):
                malos = dict(self.lote.archivos)
                malos[nombre] = contenido
                # El json declara los hashes viejos: se corrigen para aislar el caso.
                base = nombre.rsplit("_", 1)[0]
                meta = json.loads(malos[f"{base}.json"])
                clave = "foto" if "foto" in nombre else "recorte"
                meta["archivos"]["sha256"][clave] = _sha(contenido)
                malos[f"{base}.json"] = _json_bytes(meta)
                ruta = escribir_zip(self.dir / "x.zip", malos, manifiesto_de(malos))

                self.assertIn("no es de la clase que indica el nombre", self.problemas(ruta))

    def test_heic_con_su_cabecera_pasa(self):
        base = nombre_base("P2", "BAJ", "D1", "R3")
        foto = b"\x00\x00\x00\x18ftypheic" + _relleno("heic")
        recorte = _png("heic-recorte")
        meta = metadatos("P2", "BAJ", "D1", "R3", _sha(foto), _sha(recorte))
        meta["archivos"]["foto"] = f"{base}_foto.heic"
        archivos = {f"{base}_foto.heic": foto, f"{base}_recorte.png": recorte, f"{base}.json": _json_bytes(meta)}
        ruta = escribir_zip(self.dir / "x.zip", archivos, manifiesto_de(archivos))

        self.assertTrue(il.verificar_lote(ruta).ok)

    def test_tope_de_archivos(self):
        self.assertIn("demasiados archivos", self.problemas(self.lote.zip(), max_archivos=2))

    def test_tope_de_bytes(self):
        self.assertIn("el tope es", self.problemas(self.lote.zip(), max_bytes=100))

    def test_junta_todos_los_problemas_no_solo_el_primero(self):
        malos = dict(self.lote.archivos)
        for n in ("P3_LEDC_D2_R1_G_foto.jpg", "P3_VEN_D2_R1_G_foto.jpg"):
            malos[n] = malos[n][:20] + b"\x01" + malos[n][21:]
        ruta = escribir_zip(self.dir / "x.zip", malos, self.lote.manifiesto)

        r = il.verificar_lote(ruta)

        self.assertGreaterEqual(sum("el SHA-256 no coincide" in p for p in r.problemas), 2)

    def test_un_zip_corrompido_nunca_lanza_una_excepcion(self):
        # Fuzz con semilla fija: voltear bytes al azar de un zip valido. El script
        # puede rechazarlo (casi siempre) o aceptarlo (si cae en una marca de
        # tiempo que ningun hash cubre), pero nunca debe morir con un traceback.
        # Esta prueba encontro un UnicodeDecodeError con un nombre dañado.
        import random

        datos = self.lote.zip().read_bytes()
        rnd = random.Random(7)
        ruta = self.dir / "fuzz.zip"
        excepciones = []
        for _ in range(300):
            b = bytearray(datos)
            for _ in range(rnd.choice([1, 1, 1, 3, 10])):
                b[rnd.randrange(len(b))] ^= rnd.randrange(1, 256)
            ruta.write_bytes(bytes(b))
            try:
                self.assertIsInstance(il.verificar_lote(ruta), il.Resultado)
            except Exception as e:  # noqa: BLE001 - justamente lo que se busca
                excepciones.append(f"{type(e).__name__}: {e}")
        self.assertEqual(excepciones, [])

    def test_un_zip_truncado_nunca_lanza_una_excepcion(self):
        datos = self.lote.zip().read_bytes()
        ruta = self.dir / "cortado.zip"
        for corte in list(range(0, len(datos), max(1, len(datos) // 80))) + [len(datos) - 1, len(datos) - 22]:
            ruta.write_bytes(datos[:corte])
            r = il.verificar_lote(ruta)
            self.assertFalse(r.ok, f"un zip cortado en {corte} no puede pasar")

    def test_un_nombre_de_entrada_dañado_se_informa(self):
        ruta = self.lote.zip()
        datos = bytearray(ruta.read_bytes())
        i = datos.index(b"P3_LEDC_D2_R1_G_foto.jpg")
        datos[i + 3] = 0xD3  # un byte que no es UTF-8 valido en mitad del nombre
        ruta.write_bytes(bytes(datos))

        r = il.verificar_lote(ruta)

        self.assertFalse(r.ok)

    def test_verificar_no_escribe_nada(self):
        ruta = self.lote.zip()
        antes = sorted(p.name for p in self.dir.iterdir())

        il.verificar_lote(ruta)

        self.assertEqual(sorted(p.name for p in self.dir.iterdir()), antes)


class Destino(Base):
    def setUp(self):
        super().setUp()
        self.boveda = (self.dir / "boveda").resolve()
        self.boveda.mkdir()

    def test_destinos_validos(self):
        for d, esperado in (("lote_ab12cd34", "lote_ab12cd34"), ("2026-10/lote1", "2026-10/lote1")):
            with self.subTest(d):
                self.assertEqual(il.resolver_destino(self.boveda, d), (self.boveda / Path(*esperado.split("/"))).resolve())

    def test_destinos_que_se_salen_o_son_raros(self):
        for d in ("", "..", "../fuera", "a/../b", "/abs", "C:\\x", "C:/x", "a b", ".oculto", "a//b", "..\\x", "\\\\red\\x"):
            with self.subTest(repr(d)):
                with self.assertRaises(il.ErrorDeConfiguracion):
                    il.resolver_destino(self.boveda, d)


class Copia(Base):
    def setUp(self):
        super().setUp()
        self.boveda = self.dir / "boveda"
        self.boveda.mkdir()
        self.zip = self.lote.zip()
        self.r = il.verificar_lote(self.zip)
        self.destino = self.boveda / "lote_1"

    def nombres(self, carpeta: Path) -> list[str]:
        return sorted(p.name for p in carpeta.iterdir())

    def test_copia_todo_mas_el_manifiesto(self):
        final = il.copiar_lote(self.zip, self.r, self.destino)

        self.assertEqual(final, self.destino)
        self.assertEqual(self.nombres(self.destino), sorted(list(self.lote.archivos) + [il.NOMBRE_MANIFIESTO]))
        for n, d in self.lote.archivos.items():
            self.assertEqual((self.destino / n).read_bytes(), d, n)

    def test_el_manifiesto_copiado_es_el_original(self):
        il.copiar_lote(self.zip, self.r, self.destino)

        copiado = json.loads((self.destino / il.NOMBRE_MANIFIESTO).read_text())
        self.assertEqual(copiado, self.lote.manifiesto)

    def test_no_deja_la_carpeta_temporal(self):
        il.copiar_lote(self.zip, self.r, self.destino)

        self.assertEqual(self.nombres(self.boveda), ["lote_1"])

    def test_no_sobrescribe(self):
        self.destino.mkdir()
        (self.destino / "mio.txt").write_text("importante")

        with self.assertRaises(il.ErrorDeCopia):
            il.copiar_lote(self.zip, self.r, self.destino)

        self.assertEqual(self.nombres(self.destino), ["mio.txt"])
        self.assertEqual((self.destino / "mio.txt").read_text(), "importante")

    def test_no_pisa_una_importacion_a_medias(self):
        (self.boveda / ".lote_1.importando").mkdir()

        with self.assertRaises(il.ErrorDeCopia):
            il.copiar_lote(self.zip, self.r, self.destino)

        self.assertFalse(self.destino.exists())
        self.assertTrue((self.boveda / ".lote_1.importando").exists(), "no borra lo que no creo")

    def test_un_lote_que_no_paso_la_verificacion_no_se_copia(self):
        malo = il.Resultado(problemas=["algo"])

        with self.assertRaises(il.ErrorDeCopia):
            il.copiar_lote(self.zip, malo, self.destino)

        self.assertEqual(self.nombres(self.boveda), [])

    def test_si_falla_a_mitad_no_queda_nada(self):
        original = il._copiar_entrada
        llamadas = []

        def falla_en_la_tercera(zf, nombre, destino, esperado):
            llamadas.append(nombre)
            if len(llamadas) == 3:
                raise OSError("disco lleno")
            return original(zf, nombre, destino, esperado)

        with mock.patch.object(il, "_copiar_entrada", falla_en_la_tercera):
            with self.assertRaises(il.ErrorDeCopia):
                il.copiar_lote(self.zip, self.r, self.destino)

        self.assertEqual(len(llamadas), 3)
        self.assertEqual(self.nombres(self.boveda), [], "ni destino ni temporal")

    def test_si_aparece_un_archivo_intruso_en_la_carpeta_copiada(self):
        original = il._copiar_entrada

        def deja_un_intruso(zf, nombre, destino, esperado):
            original(zf, nombre, destino, esperado)
            (destino.parent / "intruso.txt").write_text("no deberia estar")

        with mock.patch.object(il, "_copiar_entrada", deja_un_intruso):
            with self.assertRaises(il.ErrorDeCopia) as cm:
                il.copiar_lote(self.zip, self.r, self.destino)

        self.assertIn("no tiene los archivos esperados", str(cm.exception))
        self.assertEqual(self.nombres(self.boveda), [])

    def test_si_la_boveda_corrompe_un_archivo_se_detecta_al_releer(self):
        original = il._copiar_entrada

        def corrompe_despues_de_escribir(zf, nombre, destino, esperado):
            original(zf, nombre, destino, esperado)
            if nombre.endswith("_foto.jpg"):
                destino.write_bytes(destino.read_bytes()[:-1] + b"\x00")

        with mock.patch.object(il, "_copiar_entrada", corrompe_despues_de_escribir):
            with self.assertRaises(il.ErrorDeCopia) as cm:
                il.copiar_lote(self.zip, self.r, self.destino)

        self.assertIn("despues de copiarlo", str(cm.exception))
        self.assertEqual(self.nombres(self.boveda), [])

    def test_si_el_zip_cambia_entre_verificar_y_copiar_se_detecta(self):
        # Se verifica el zip bueno y se reemplaza por otro con la misma forma.
        malos = dict(self.lote.archivos)
        malos["P3_LEDC_D2_R1_G_foto.jpg"] = _jpg("cambiado")
        escribir_zip(self.zip, malos, self.lote.manifiesto)

        with self.assertRaises(il.ErrorDeCopia) as cm:
            il.copiar_lote(self.zip, self.r, self.destino)

        self.assertIn("cambio entre la verificacion y la copia", str(cm.exception))
        self.assertEqual(self.nombres(self.boveda), [])

    def test_un_destino_anidado_se_crea(self):
        destino = il.resolver_destino(self.boveda.resolve(), "2026-10/lote_1")

        il.copiar_lote(self.zip, self.r, destino)

        self.assertTrue((destino / il.NOMBRE_MANIFIESTO).exists())


class Configuracion(Base):
    def escribir(self, contenido, nombre="config.json") -> Path:
        ruta = self.dir / nombre
        ruta.write_text(contenido if isinstance(contenido, str) else json.dumps(contenido), encoding="utf-8")
        return ruta

    def test_config_valida(self):
        boveda = self.dir / "boveda"
        boveda.mkdir()

        self.assertEqual(il.cargar_boveda(self.escribir({"boveda": str(boveda)})), boveda.resolve())

    def test_config_inexistente_explica_como_crearla(self):
        with self.assertRaises(il.ErrorDeConfiguracion) as cm:
            il.cargar_boveda(self.dir / "no_existe.json")

        self.assertIn("boveda", str(cm.exception))

    def test_config_mal_formada(self):
        boveda = self.dir / "boveda"
        boveda.mkdir()
        for malo in ("{ no json", "[]", {"boveda": 5}, {"boveda": str(boveda), "otra": 1}, {}):
            with self.subTest(repr(malo)):
                with self.assertRaises(il.ErrorDeConfiguracion):
                    il.cargar_boveda(self.escribir(malo))

    def test_boveda_que_no_existe(self):
        with self.assertRaises(il.ErrorDeConfiguracion) as cm:
            il.cargar_boveda(self.escribir({"boveda": str(self.dir / "nada")}))

        self.assertIn("Cryptomator", str(cm.exception))

    def test_la_config_no_puede_estar_en_un_repositorio(self):
        repo = self.dir / "repo"
        (repo / ".git").mkdir(parents=True)
        boveda = self.dir / "boveda"
        boveda.mkdir()
        ruta = repo / "config.json"
        ruta.write_text(json.dumps({"boveda": str(boveda)}))

        with self.assertRaises(il.ErrorDeConfiguracion) as cm:
            il.cargar_boveda(ruta)

        self.assertIn("dentro del repositorio", str(cm.exception))

    def test_la_boveda_no_puede_estar_en_un_repositorio(self):
        repo = self.dir / "repo"
        (repo / ".git").mkdir(parents=True)
        (repo / "profundo" / "boveda").mkdir(parents=True)

        with self.assertRaises(il.ErrorDeConfiguracion) as cm:
            il.cargar_boveda(self.escribir({"boveda": str(repo / "profundo" / "boveda")}))

        self.assertIn("dentro del repositorio", str(cm.exception))

    def test_un_git_que_es_archivo_tambien_cuenta(self):
        # Los worktrees y submodulos tienen .git como archivo.
        repo = self.dir / "worktree"
        (repo / "boveda").mkdir(parents=True)
        (repo / ".git").write_text("gitdir: /otro/sitio")

        with self.assertRaises(il.ErrorDeConfiguracion):
            il.cargar_boveda(self.escribir({"boveda": str(repo / "boveda")}))

    def test_ruta_por_defecto_respeta_la_variable_de_entorno(self):
        with mock.patch.dict("os.environ", {"WEARHACK_IMPORTAR_LOTE_CONFIG": "/x/y.json"}):
            self.assertEqual(il.ruta_de_configuracion_por_defecto(), Path("/x/y.json"))
        with mock.patch.dict("os.environ", {}, clear=True), mock.patch.object(Path, "home", return_value=Path("/h")):
            self.assertEqual(il.ruta_de_configuracion_por_defecto(), Path("/h/.wearhack/importar_lote.json"))

    def test_sin_directorio_personal_es_un_error_de_configuracion_no_un_traceback(self):
        with mock.patch.dict("os.environ", {}, clear=True),              mock.patch.object(Path, "home", side_effect=RuntimeError("sin home")):
            with self.assertRaises(il.ErrorDeConfiguracion):
                il.ruta_de_configuracion_por_defecto()

    def test_el_script_no_se_pone_a_si_mismo_dentro_de_un_repositorio_por_defecto(self):
        # La ruta por defecto vive en el directorio personal, fuera de cualquier repo.
        with mock.patch.dict("os.environ", {}, clear=True), mock.patch.object(Path, "home", return_value=self.dir):
            self.assertIsNone(il.esta_en_un_repositorio(il.ruta_de_configuracion_por_defecto().parent))


class LineaDeComandos(Base):
    def setUp(self):
        super().setUp()
        self.boveda = self.dir / "boveda"
        self.boveda.mkdir()
        self.config = self.dir / "config.json"
        self.config.write_text(json.dumps({"boveda": str(self.boveda)}))

    def correr(self, *args) -> tuple[int, str]:
        salida = io.StringIO()
        codigo = il.principal([str(a) for a in args], salida=salida)
        return codigo, salida.getvalue()

    def test_importa_y_muestra_el_hash_y_el_prefijo(self):
        zip_ = self.lote.zip()

        codigo, texto = self.correr(zip_, "--config", self.config)

        self.assertEqual(codigo, 0, texto)
        esperado = self.lote.manifiesto["hash_global"]
        self.assertIn(f"Hash global: {esperado}", texto)
        self.assertIn(f"escribe: {esperado[:8]}", texto)
        self.assertIn("Copiado a", texto)
        self.assertTrue((self.boveda / "lote" / il.NOMBRE_MANIFIESTO).exists())

    def test_el_destino_por_defecto_es_el_nombre_del_zip(self):
        self.lote.nombre = "lote_ab12cd34.zip"

        self.correr(self.lote.zip(), "--config", self.config)

        self.assertTrue((self.boveda / "lote_ab12cd34").is_dir())

    def test_destino_explicito(self):
        codigo, _ = self.correr(self.lote.zip(), "--config", self.config, "--destino", "sesion1/p3_d2")

        self.assertEqual(codigo, 0)
        self.assertTrue((self.boveda / "sesion1" / "p3_d2").is_dir())

    def test_un_lote_malo_sale_con_1_y_no_copia_nada(self):
        malos = dict(self.lote.archivos)
        malos["P3_LEDC_D2_R1_G_foto.jpg"] = _jpg("otro")
        escribir_zip(self.dir / "lote.zip", malos, self.lote.manifiesto)

        codigo, texto = self.correr(self.dir / "lote.zip", "--config", self.config)

        self.assertEqual(codigo, 1)
        self.assertIn("EL LOTE NO PASA LA VERIFICACION", texto)
        self.assertIn("No se copio nada", texto)
        self.assertEqual(list(self.boveda.iterdir()), [])

    def test_solo_verificar_no_necesita_config_y_no_escribe(self):
        zip_ = self.lote.zip()
        antes = sorted(p.name for p in self.dir.iterdir())

        codigo, texto = self.correr(zip_, "--solo-verificar", "--config", self.dir / "no_existe.json")

        self.assertEqual(codigo, 0, texto)
        self.assertIn("Solo verificacion", texto)
        self.assertIn(self.lote.manifiesto["hash_global"], texto)
        self.assertEqual(sorted(p.name for p in self.dir.iterdir()), antes)
        self.assertEqual(list(self.boveda.iterdir()), [])

    def test_solo_verificar_tambien_falla_con_un_lote_malo(self):
        codigo, _ = self.correr(self.lote.zip(manifiesto=None), "--solo-verificar")

        self.assertEqual(codigo, 1)

    def test_zip_inexistente_sale_con_2(self):
        codigo, texto = self.correr(self.dir / "nada.zip", "--config", self.config)

        self.assertEqual(codigo, 2)
        self.assertIn("No existe el archivo", texto)

    def test_config_inexistente_sale_con_2_antes_de_leer_el_zip(self):
        codigo, texto = self.correr(self.lote.zip(), "--config", self.dir / "no.json")

        self.assertEqual(codigo, 2)
        self.assertIn("ERROR de configuracion", texto)

    def test_destino_peligroso_sale_con_2_y_no_copia_nada(self):
        codigo, _ = self.correr(self.lote.zip(), "--config", self.config, "--destino", "../fuera")

        self.assertEqual(codigo, 2)
        self.assertEqual(list(self.boveda.iterdir()), [])
        self.assertFalse((self.dir / "fuera").exists())

    def test_importar_dos_veces_el_mismo_lote_no_sobrescribe(self):
        zip_ = self.lote.zip()
        self.correr(zip_, "--config", self.config)

        codigo, texto = self.correr(zip_, "--config", self.config)

        self.assertEqual(codigo, 1)
        self.assertIn("ya existe", texto)

    def test_no_imprime_nada_que_no_sean_seudonimos(self):
        _, texto = self.correr(self.lote.zip(), "--config", self.config)

        self.assertNotIn("Modelo de prueba", texto)


if __name__ == "__main__":
    unittest.main()
