"""Pruebas del script de demo. Solo libreria estandar, sin fotos de personas:

    python -m unittest discover -s tools/demo -v
"""

import json
import sys
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import demo_colorimetria as demo  # noqa: E402

RESULTADO = {
    "temporada": "OTONO",
    "confianza": 0.41,
    "ejes": ["piel_L", "cabello_a"],
    "piel": {"l": 62.0, "a": 14.0, "b": 18.0},
    "cabello": None,
    "iris": {"l": 25.0, "a": 6.0, "b": 9.0},
    "segunda_opcion": "PRIMAVERA",
    "probabilidades": {
        "estaciones": {"PRIMAVERA": 0.3, "VERANO": 0.1, "OTONO": 0.41, "INVIERNO": 0.19},
        "subtono": {"CALIDO": 0.71, "FRIO": 0.29},
        "contraste": {"ALTO": 0.6, "BAJO": 0.4},
    },
    "version_centroides": "4-estaciones-v1",
    "experimental": "Solo MVP academico <b>sin</b> uso comercial",
}


class TestColor(unittest.TestCase):
    def test_lab_a_hex(self):
        self.assertEqual(demo.lab_a_hex(100, 0, 0), "#ffffff")
        self.assertEqual(demo.lab_a_hex(0, 0, 0), "#000000")
        self.assertEqual(demo.lab_a_hex(53.2408, 80.0925, 67.2032), "#ff0000")
        # Fuera de gama se recorta en vez de fallar.
        self.assertRegex(demo.lab_a_hex(50, 200, -200), r"^#[0-9a-f]{6}$")


class TestPagina(unittest.TestCase):
    def test_resultado_muestra_estacion_probabilidades_y_colores(self):
        pagina = demo.pagina_resultado(RESULTADO, b"\x89PNG")
        self.assertIn("Otoño", pagina)
        self.assertIn("segunda opción: Primavera", pagina)
        self.assertIn("41%", pagina)
        self.assertIn("No visible", pagina)  # cabello en null: no se inventa
        self.assertIn("data:image/png;base64,", pagina)
        # El texto del servicio se escapa.
        self.assertIn("&lt;b&gt;sin&lt;/b&gt;", pagina)
        self.assertNotIn("<b>sin</b>", pagina)

    def test_sin_foto_no_incrusta_la_imagen(self):
        self.assertNotIn("base64", demo.pagina_resultado(RESULTADO, None))

    def test_errores(self):
        self.assertIn("Repite la foto", demo.pagina_error(422, {"detail": "No se detecto un rostro"}, None))
        self.assertIn("sin centroides", demo.pagina_error(503, {}, None))
        self.assertIn("No hay servicio", demo.pagina_error(0, {"detail": "refused"}, None))
        validacion = demo.pagina_error(422, {"detail": [{"msg": "campo invalido"}]}, None)
        self.assertIn("campo invalido", validacion)


class _Servicio(BaseHTTPRequestHandler):
    respuestas: list[tuple[int, dict]] = []
    recibido: list[tuple[str, str, bytes]] = []

    def do_POST(self):  # noqa: N802
        cuerpo = self.rfile.read(int(self.headers["content-length"]))
        type(self).recibido.append((self.path, self.headers["content-type"], cuerpo))
        codigo, datos = type(self).respuestas.pop(0)
        texto = json.dumps(datos).encode()
        self.send_response(codigo)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(texto)))
        self.end_headers()
        self.wfile.write(texto)

    def log_message(self, *_):
        pass


class TestServicio(unittest.TestCase):
    def setUp(self):
        self.servidor = HTTPServer(("127.0.0.1", 0), _Servicio)
        threading.Thread(target=self.servidor.serve_forever, daemon=True).start()
        self.url = f"http://127.0.0.1:{self.servidor.server_port}"
        _Servicio.recibido.clear()

    def tearDown(self):
        self.servidor.shutdown()
        self.servidor.server_close()

    def test_manda_el_png_a_la_ruta_del_servicio(self):
        _Servicio.respuestas[:] = [(200, RESULTADO)]
        codigo, cuerpo = demo.analizar(self.url, b"\x89PNG datos")
        self.assertEqual(codigo, 200)
        self.assertEqual(cuerpo["temporada"], "OTONO")
        self.assertEqual(_Servicio.recibido, [("/v1/colorimetria/analizar", "image/png", b"\x89PNG datos")])

    def test_un_422_trae_su_motivo(self):
        _Servicio.respuestas[:] = [(422, {"detail": "No se detecto un rostro en el recorte"})]
        codigo, cuerpo = demo.analizar(self.url, b"\x89PNG")
        self.assertEqual(codigo, 422)
        self.assertIn("rostro", cuerpo["detail"])

    def test_sin_servicio_devuelve_codigo_cero(self):
        puerto = self.servidor.server_port
        self.tearDown()
        codigo, _ = demo.analizar(f"http://127.0.0.1:{puerto}", b"\x89PNG", timeout=2)
        self.assertEqual(codigo, 0)
        self.setUp()


if __name__ == "__main__":
    unittest.main()
