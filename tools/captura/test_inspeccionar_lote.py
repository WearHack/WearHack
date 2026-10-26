"""Pruebas de inspeccionar_lote.py.

    python -m unittest discover -s tools/captura -v

Los JPEG, EXIF, perfiles ICC y PNG se fabrican a mano en memoria: no entra ninguna foto
al repositorio. Los JPEG no son decodificables (no hacen falta): llevan solo los
segmentos que el inspector lee.
"""

from __future__ import annotations

import io
import json
import random
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

import inspeccionar_lote as il
from test_importar_lote import _json_bytes, metadatos, nombre_base


def tag_ifd(e: str, tag: int, tipo: int, cuenta: int, valor: bytes) -> bytes:
    return struct.pack(e + "HHI", tag, tipo, cuenta) + valor.ljust(4, b"\x00")


def app1_exif(e="<", orientacion=None, iso=None, exposicion=None, wb=None) -> bytes:
    """Un segmento APP1 con un TIFF de Exif: IFD0 (orientacion) y sub-IFD (resto)."""
    sub = []
    datos_extra = b""
    # Los valores de 8 bytes (racional) van fuera de la entrada, tras las tablas.
    if iso is not None:
        sub.append((0x8827, 3, 1, struct.pack(e + "H", iso)))
    if exposicion is not None:
        sub.append((0xA000_0000, 0, 0, b""))  # marcador: se resuelve abajo
        sub.pop()
    if wb is not None:
        sub.append((0xA403, 3, 1, struct.pack(e + "H", wb)))
    entradas_raiz = []
    if orientacion is not None:
        entradas_raiz.append((0x0112, 3, 1, struct.pack(e + "H", orientacion)))

    # Disposicion: cabecera(8) | IFD0 | sub-IFD | racional
    n_raiz = len(entradas_raiz) + 1  # + puntero al sub-IFD
    tam_raiz = 2 + 12 * n_raiz + 4
    off_sub = 8 + tam_raiz
    n_sub = len(sub) + (1 if exposicion is not None else 0)
    tam_sub = 2 + 12 * n_sub + 4
    off_racional = off_sub + tam_sub

    raiz = struct.pack(e + "H", n_raiz)
    for t, ty, c, v in entradas_raiz:
        raiz += tag_ifd(e, t, ty, c, v)
    raiz += tag_ifd(e, 0x8769, 4, 1, struct.pack(e + "I", off_sub))
    raiz += struct.pack(e + "I", 0)

    cuerpo_sub = struct.pack(e + "H", n_sub)
    entradas = list(sub)
    for t, ty, c, v in entradas:
        cuerpo_sub += tag_ifd(e, t, ty, c, v)
    if exposicion is not None:
        cuerpo_sub += tag_ifd(e, 0x829A, 5, 1, struct.pack(e + "I", off_racional))
        datos_extra = struct.pack(e + "II", *exposicion)
    cuerpo_sub += struct.pack(e + "I", 0)

    cabecera = (b"II" if e == "<" else b"MM") + struct.pack(e + "HI", 42, 8)
    tiff = cabecera + raiz + cuerpo_sub + datos_extra
    cuerpo = b"Exif\x00\x00" + tiff
    return b"\xff\xe1" + struct.pack(">H", len(cuerpo) + 2) + cuerpo


def perfil_icc(nombre: str | None, v4=False, espacio=b"RGB ") -> bytes:
    cab = bytearray(128)
    cab[16:20] = espacio
    cab[36:40] = b"acsp"
    if nombre is None:
        tabla = struct.pack(">I", 0)
        total = 128 + len(tabla)
        cab[0:4] = struct.pack(">I", total)
        return bytes(cab) + tabla
    if v4:
        texto = nombre.encode("utf-16-be")
        tag = b"mluc" + b"\0" * 4 + struct.pack(">II", 1, 12) + b"enUS" + struct.pack(">II", len(texto), 28) + texto
    else:
        ascii_ = nombre.encode("latin-1") + b"\x00"
        tag = b"desc" + b"\0" * 4 + struct.pack(">I", len(ascii_)) + ascii_
    inicio = 128 + 4 + 12
    tabla = struct.pack(">I", 1) + b"desc" + struct.pack(">II", inicio, len(tag))
    cab[0:4] = struct.pack(">I", inicio + len(tag))
    return bytes(cab) + tabla + tag


def app2_icc(perfil: bytes, partes=1, orden=None) -> bytes:
    trozo = -(-len(perfil) // partes)
    segs = b""
    for k in (orden if orden is not None else range(partes)):
        c = perfil[k * trozo:(k + 1) * trozo]
        cuerpo = b"ICC_PROFILE\x00" + bytes([k + 1, partes]) + c
        segs += b"\xff\xe2" + struct.pack(">H", len(cuerpo) + 2) + cuerpo
    return segs


def jpeg(ancho=4000, alto=3000, *segmentos: bytes, despues: tuple = ()) -> bytes:
    sof = b"\xff\xc0" + struct.pack(">HBHHB", 8 + 3 * 3, 8, alto, ancho, 3) + b"\x01\x22\x00\x02\x11\x01\x03\x11\x01"
    return b"\xff\xd8" + b"".join(segmentos) + sof + b"".join(despues) + b"\xff\xd9"


def png(ancho=600, alto=700, tipo_de_color=2, profundidad=8, icc=False) -> bytes:
    def chunk(t: bytes, c: bytes) -> bytes:
        return struct.pack(">I", len(c)) + t + c + b"\0\0\0\0"

    ihdr = struct.pack(">IIBBBBB", ancho, alto, profundidad, tipo_de_color, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + (chunk(b"iCCP", b"perfil\x00\x00x") if icc else b"")
            + chunk(b"IDAT", b"") + chunk(b"IEND", b""))


def escribir_toma(carpeta: Path, foto: bytes, recorte: bytes, perfil_foto: str,
                  perfil_recorte="sRGB (convertido por la app)", bbox=(100, 100, 400, 500),
                  seudonimo="P3", luz="LEDC", celular="D2", rep="R1", ext="jpg", espejo=None) -> str:
    base = nombre_base(seudonimo, luz, celular, rep)
    meta = metadatos(seudonimo, luz, celular, rep)
    meta["perfil_color"] = {"foto": perfil_foto, "recorte": perfil_recorte}
    meta["rostro"]["bbox"] = list(bbox)
    meta["camara"]["espejo"] = espejo
    meta["archivos"]["foto"] = f"{base}_foto.{ext}"
    (carpeta / f"{base}_foto.{ext}").write_bytes(foto)
    (carpeta / f"{base}_recorte.png").write_bytes(recorte)
    (carpeta / f"{base}.json").write_bytes(_json_bytes(meta))
    return base


class Base(unittest.TestCase):
    def setUp(self):
        self._t = tempfile.TemporaryDirectory(prefix="wearhack_insp_")
        self.addCleanup(self._t.cleanup)
        self.dir = Path(self._t.name)

    def hallazgos(self) -> str:
        return " | ".join(il.inspeccionar(self.dir).hallazgos)


class LecturaDeJpeg(unittest.TestCase):
    def test_dimensiones(self):
        j = il.leer_jpeg(jpeg(4032, 3024))

        self.assertEqual((j.ancho, j.alto), (4032, 3024))

    def test_exif_little_endian(self):
        j = il.leer_jpeg(jpeg(4000, 3000, app1_exif("<", 6, 400, (1, 60), 0)))

        self.assertEqual(j.orientacion, 6)
        self.assertEqual(j.iso, 400)
        self.assertAlmostEqual(j.exposicion, 1 / 60)
        self.assertEqual(j.balance_blancos, 0)

    def test_exif_big_endian(self):
        j = il.leer_jpeg(jpeg(4000, 3000, app1_exif(">", 3, 100, (1, 250), 1)))

        self.assertEqual((j.orientacion, j.iso, j.balance_blancos), (3, 100, 1))
        self.assertAlmostEqual(j.exposicion, 1 / 250)

    def test_lo_que_falta_es_none(self):
        j = il.leer_jpeg(jpeg(4000, 3000, app1_exif("<", 1)))

        self.assertEqual(j.orientacion, 1)
        self.assertIsNone(j.iso)
        self.assertIsNone(j.exposicion)
        self.assertIsNone(j.balance_blancos)

    def test_sin_exif(self):
        j = il.leer_jpeg(jpeg())

        self.assertIsNone(j.orientacion)
        self.assertIsNone(j.perfil)

    def test_perfil_icc_en_un_segmento(self):
        p = perfil_icc("Display P3")
        j = il.leer_jpeg(jpeg(4000, 3000, app2_icc(p)))

        self.assertEqual(j.perfil, p)

    def test_perfil_icc_en_varios_segmentos(self):
        p = perfil_icc("Display P3") + b"\x07" * 5000
        j = il.leer_jpeg(jpeg(4000, 3000, app2_icc(p, partes=3)))

        self.assertEqual(j.perfil, p)

    def test_los_fragmentos_del_perfil_se_ordenan_por_secuencia(self):
        p = perfil_icc("Display P3") + bytes(range(256)) * 20
        j = il.leer_jpeg(jpeg(4000, 3000, app2_icc(p, partes=3, orden=[2, 0, 1])))

        self.assertEqual(j.perfil, p)

    def test_la_tabla_de_huffman_no_se_confunde_con_las_dimensiones(self):
        # En un JPEG real la tabla de Huffman (DHT) va DESPUES del SOF, y trae
        # bytes que, leidos como dimensiones, darian cualquier cosa.
        dht = b"\xff\xc4" + struct.pack(">H", 19) + bytes([0x00]) + bytes(range(1, 17))
        j = il.leer_jpeg(jpeg(4032, 3024, despues=(dht,)))

        self.assertEqual((j.ancho, j.alto), (4032, 3024))

    def test_un_perfil_sin_la_firma_acsp_no_se_lee(self):
        p = bytearray(perfil_icc("Display P3"))
        p[36:40] = b"xxxx"

        self.assertIsNone(il.descripcion_de_perfil(bytes(p)))

    def test_algo_que_no_es_un_jpeg(self):
        self.assertTrue(il.leer_jpeg(b"no soy un jpeg").problemas)

    def test_nombre_del_perfil_v2_y_v4(self):
        for nombre in ("Display P3", "sRGB IEC61966-2.1", "Perfil de prueba"):
            for v4 in (False, True):
                with self.subTest(nombre=nombre, v4=v4):
                    self.assertEqual(il.descripcion_de_perfil(perfil_icc(nombre, v4=v4)), nombre)

    def test_perfil_sin_nombre_o_roto(self):
        self.assertIsNone(il.descripcion_de_perfil(perfil_icc(None)))
        self.assertIsNone(il.descripcion_de_perfil(b"corto"))
        self.assertIsNone(il.descripcion_de_perfil(perfil_icc("Display P3")[:140]))


class LecturaDePng(unittest.TestCase):
    def test_dimensiones_y_tipo(self):
        p = il.leer_png(png(600, 700))

        self.assertEqual((p.ancho, p.alto, p.profundidad, p.tipo_de_color), (600, 700, 8, 2))
        self.assertEqual(p.chunks_de_color, [])

    def test_ve_un_perfil_incrustado(self):
        self.assertEqual(il.leer_png(png(icc=True)).chunks_de_color, ["iCCP"])

    def test_algo_que_no_es_un_png(self):
        self.assertTrue(il.leer_png(b"nada").problemas)


class Inspeccion(Base):
    def toma_iphone(self, **kw):
        icc = perfil_icc("Display P3")
        return escribir_toma(
            self.dir,
            jpeg(4032, 3024, app1_exif("<", 6, 50, (1, 60), 0), app2_icc(icc)),
            png(),
            "Display P3",
            bbox=(100, 100, 400, 500),
            **kw,
        )

    def test_una_toma_de_iphone_coherente_no_tiene_hallazgos(self):
        self.toma_iphone()

        inf = il.inspeccionar(self.dir)

        self.assertEqual(inf.hallazgos, [])
        self.assertEqual(inf.resumen["tomas"], 1)
        self.assertEqual(inf.resumen["fotos_jpeg"], 1)
        self.assertEqual(inf.resumen["con_perfil_icc"], 1)
        self.assertEqual(inf.resumen["perfiles"], {"Display P3": 1})
        self.assertEqual(inf.resumen["con_iso"], 1)
        self.assertEqual(inf.resumen["orientaciones_exif"], {6: 1})

    def test_el_json_dice_srgb_pero_la_foto_es_display_p3(self):
        icc = perfil_icc("Display P3")
        escribir_toma(self.dir, jpeg(4032, 3024, app2_icc(icc)), png(), "sRGB")

        self.assertIn("perfil_color.foto dice 'sRGB' pero el perfil real de la foto es 'Display P3'", self.hallazgos())

    def test_foto_sin_perfil_y_json_que_lo_reconoce(self):
        escribir_toma(self.dir, jpeg(), png(), il.PERFIL_SUPUESTO)

        self.assertEqual(il.inspeccionar(self.dir).hallazgos, [])
        self.assertEqual(il.inspeccionar(self.dir).resumen["perfiles"], {"(sin perfil)": 1})

    def test_foto_sin_perfil_pero_el_json_inventa_uno(self):
        escribir_toma(self.dir, jpeg(), png(), "Display P3")

        self.assertIn("perfil_color.foto", self.hallazgos())

    def test_perfil_sin_nombre(self):
        escribir_toma(self.dir, jpeg(4000, 3000, app2_icc(perfil_icc(None))), png(), il.PERFIL_SIN_NOMBRE)

        self.assertEqual(il.inspeccionar(self.dir).hallazgos, [])

    def test_un_recorte_con_perfil_incrustado_se_senala(self):
        escribir_toma(self.dir, jpeg(), png(icc=True), il.PERFIL_SUPUESTO)

        self.assertIn("perfil ICC incrustado", self.hallazgos())

    def test_un_recorte_con_canal_alfa_se_senala(self):
        escribir_toma(self.dir, jpeg(), png(tipo_de_color=6), il.PERFIL_SUPUESTO)

        self.assertIn("no es RGB de 8 bits", self.hallazgos())

    def test_un_recorte_de_16_bits_se_senala(self):
        escribir_toma(self.dir, jpeg(), png(profundidad=16), il.PERFIL_SUPUESTO)

        self.assertIn("no es RGB de 8 bits", self.hallazgos())

    def test_el_json_dice_otro_perfil_para_el_recorte(self):
        escribir_toma(self.dir, jpeg(), png(), il.PERFIL_SUPUESTO, perfil_recorte="Display P3")

        self.assertIn("perfil_color.recorte", self.hallazgos())

    def test_el_recuadro_cabe_en_la_foto_orientada(self):
        # 4000x3000 con EXIF 6 queda 3000x4000. Un recuadro de 3500 de ancho NO cabe.
        escribir_toma(self.dir, jpeg(4000, 3000, app1_exif("<", 6)), png(), il.PERFIL_SUPUESTO,
                      bbox=(100, 100, 3500, 300))

        self.assertIn("no cabe en la foto orientada 3000x4000", self.hallazgos())

    def test_el_mismo_recuadro_cabe_si_la_foto_no_gira(self):
        escribir_toma(self.dir, jpeg(4000, 3000, app1_exif("<", 1)), png(), il.PERFIL_SUPUESTO,
                      bbox=(100, 100, 3500, 300))

        self.assertEqual(il.inspeccionar(self.dir).hallazgos, [])

    def test_las_ocho_orientaciones_giran_o_no_como_dice_el_estandar(self):
        # EXIF 5 a 8 intercambian ancho y alto; 1 a 4 no. Un recuadro de 3500 de
        # ancho cabe en una foto de 4000x3000 solo si NO gira.
        for orientacion, gira in ((1, False), (2, False), (3, False), (4, False),
                                  (5, True), (6, True), (7, True), (8, True)):
            with self.subTest(orientacion=orientacion):
                for f in self.dir.iterdir():
                    f.unlink()
                escribir_toma(self.dir, jpeg(4000, 3000, app1_exif("<", orientacion)), png(),
                              il.PERFIL_SUPUESTO, bbox=(100, 100, 3500, 300))

                if gira:
                    self.assertIn("no cabe en la foto orientada 3000x4000", self.hallazgos())
                else:
                    self.assertEqual(self.hallazgos(), "")

    def test_recuadros_imposibles(self):
        for bbox in ((-5, 10, 100, 100), (200, 10, 100, 100), (10, 200, 100, 100), (10, 10, 9999, 100), (10, 10, 100, 9999)):
            with self.subTest(bbox):
                for f in self.dir.iterdir():
                    f.unlink()
                escribir_toma(self.dir, jpeg(4000, 3000), png(), il.PERFIL_SUPUESTO, bbox=bbox)

                self.assertIn("no cabe en la foto", self.hallazgos())

    def test_faltan_archivos(self):
        base = self.toma_iphone()
        (self.dir / f"{base}_recorte.png").unlink()

        self.assertIn("faltan archivos de la toma", self.hallazgos())

    def test_json_ilegible(self):
        base = self.toma_iphone()
        (self.dir / f"{base}.json").write_bytes(b"{ no json")

        self.assertIn("el JSON no se puede leer", self.hallazgos())

    def test_un_heic_no_es_una_foto_de_toma(self):
        escribir_toma(self.dir, b"\x00\x00\x00\x18ftypheic" + b"\0" * 50, png(), il.PERFIL_SUPUESTO, ext="heic")

        inf = il.inspeccionar(self.dir)

        self.assertEqual(inf.resumen["fotos_jpeg"], 0)
        self.assertTrue(inf.hallazgos, "un .heic tiene que senalarse, no pasar en silencio")

    def test_varias_tomas_se_resumen_juntas(self):
        icc = perfil_icc("Display P3")
        escribir_toma(self.dir, jpeg(4032, 3024, app1_exif("<", 6, 50, (1, 60), 0), app2_icc(icc)), png(), "Display P3", rep="R1")
        escribir_toma(self.dir, jpeg(4000, 3000), png(800, 900), il.PERFIL_SUPUESTO, rep="R2")

        r = il.inspeccionar(self.dir).resumen

        self.assertEqual(r["tomas"], 2)
        self.assertEqual(r["fotos_jpeg"], 2)
        self.assertEqual(r["con_perfil_icc"], 1)
        self.assertEqual(r["perfiles"], {"Display P3": 1, "(sin perfil)": 1})
        self.assertEqual(r["recorte_ancho_min_max"], (600, 800))

    def test_cuenta_el_espejo_de_la_camara_sin_juzgarlo(self):
        escribir_toma(self.dir, jpeg(4000, 3000), png(), il.PERFIL_SUPUESTO, rep="R1", espejo=True)
        escribir_toma(self.dir, jpeg(4000, 3000), png(), il.PERFIL_SUPUESTO, rep="R2", espejo=False)
        escribir_toma(self.dir, jpeg(4000, 3000), png(), il.PERFIL_SUPUESTO, rep="R3", espejo=None)
        escribir_toma(self.dir, jpeg(4000, 3000), png(), il.PERFIL_SUPUESTO, luz="VEN", rep="R3")

        inf = il.inspeccionar(self.dir)

        self.assertEqual(inf.resumen["espejo_camara"], {"true": 1, "false": 1, "null": 2})
        self.assertFalse(any("espejo" in h for h in inf.hallazgos))

    def test_un_zip_da_lo_mismo_que_la_carpeta(self):
        self.toma_iphone()
        z = self.dir.parent / "lote_prueba_insp.zip"
        with zipfile.ZipFile(z, "w") as zf:
            for f in sorted(self.dir.iterdir()):
                zf.write(f, f.name)
        self.addCleanup(z.unlink)

        self.assertEqual(il.inspeccionar(z).resumen, il.inspeccionar(self.dir).resumen)
        self.assertEqual(il.inspeccionar(z).hallazgos, il.inspeccionar(self.dir).hallazgos)

    def test_un_lote_vacio_no_revienta(self):
        inf = il.inspeccionar(self.dir)

        self.assertEqual(inf.resumen["tomas"], 0)
        self.assertEqual(inf.hallazgos, [])

    def test_archivos_ajenos_se_ignoran(self):
        self.toma_iphone()
        (self.dir / "manifiesto.json").write_text("{}")
        (self.dir / "notas.txt").write_text("hola")

        self.assertEqual(il.inspeccionar(self.dir).resumen["tomas"], 1)

    def test_bytes_corruptos_nunca_lanzan_una_excepcion(self):
        # Fuzz con semilla fija sobre una foto y un recorte validos.
        icc = perfil_icc("Display P3")
        foto = jpeg(4032, 3024, app1_exif("<", 6, 50, (1, 60), 0), app2_icc(icc, partes=2))
        recorte = png(icc=True)
        rnd = random.Random(11)
        fallos = []
        for _ in range(400):
            f, r = bytearray(foto), bytearray(recorte)
            for b in (f, r):
                for _ in range(rnd.choice([1, 2, 5])):
                    b[rnd.randrange(len(b))] = rnd.randrange(256)
            for x in self.dir.iterdir():
                x.unlink()
            escribir_toma(self.dir, bytes(f), bytes(r), "Display P3")
            try:
                il.inspeccionar(self.dir)
            except Exception as e:  # noqa: BLE001 - justamente lo que se busca
                fallos.append(f"{type(e).__name__}: {e}")
        self.assertEqual(fallos, [])

    def test_truncados_nunca_lanzan_una_excepcion(self):
        icc = perfil_icc("Display P3")
        foto = jpeg(4032, 3024, app1_exif("<", 6, 50, (1, 60), 0), app2_icc(icc))
        for corte in range(0, len(foto), 7):
            for x in self.dir.iterdir():
                x.unlink()
            escribir_toma(self.dir, foto[:corte], png(), "Display P3")
            il.inspeccionar(self.dir)


class LineaDeComandos(Base):
    def correr(self, *args) -> tuple[int, str]:
        s = io.StringIO()
        return il.principal([str(a) for a in args], salida=s), s.getvalue()

    def test_sin_hallazgos_sale_con_0(self):
        escribir_toma(self.dir, jpeg(), png(), il.PERFIL_SUPUESTO)

        codigo, texto = self.correr(self.dir)

        self.assertEqual(codigo, 0)
        self.assertIn("Sin hallazgos", texto)

    def test_con_hallazgos_sale_con_1_y_los_lista(self):
        escribir_toma(self.dir, jpeg(), png(icc=True), il.PERFIL_SUPUESTO)

        codigo, texto = self.correr(self.dir)

        self.assertEqual(codigo, 1)
        self.assertIn("HALLAZGOS (1)", texto)

    def test_origen_inexistente_sale_con_2(self):
        codigo, texto = self.correr(self.dir / "nada")

        self.assertEqual(codigo, 2)
        self.assertIn("No existe", texto)

    def test_un_zip_roto_sale_con_2(self):
        z = self.dir / "roto.zip"
        z.write_bytes(b"no es un zip" * 10)

        codigo, _ = self.correr(z)

        self.assertEqual(codigo, 2)

    def test_silencioso_omite_el_detalle_por_toma(self):
        escribir_toma(self.dir, jpeg(), png(), il.PERFIL_SUPUESTO)

        _, normal = self.correr(self.dir)
        _, corto = self.correr(self.dir, "--silencioso")

        self.assertIn("foto 4000x3000", normal)
        self.assertNotIn("foto 4000x3000", corto)


if __name__ == "__main__":
    unittest.main()
