"""Pruebas del mapeo de etiquetas. Solo libreria estandar:

    python -m unittest discover -s tools/entrenamiento/prendas -v
"""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import configuracion  # noqa: E402
import mapeo  # noqa: E402


class TestMapeo(unittest.TestCase):
    def test_todo_lo_mapeado_es_un_valor_de_c18(self):
        self.assertLessEqual(set(mapeo.TIPO_DESDE_FASHIONPEDIA.values()), set(mapeo.TIPOS))
        self.assertLessEqual(set(mapeo.TIPO_DESDE_GRIGOREV.values()), set(mapeo.TIPOS))
        self.assertLessEqual(set(mapeo.PATRON_DESDE_FASHIONPEDIA.values()), set(mapeo.PATRONES))

    def test_cada_tipo_y_patron_tiene_alguna_fuente(self):
        self.assertEqual(set(mapeo.TIPO_DESDE_FASHIONPEDIA.values()), set(mapeo.TIPOS))
        self.assertEqual(set(mapeo.PATRON_DESDE_FASHIONPEDIA.values()), set(mapeo.PATRONES))

    def test_joyeria_es_manual_y_no_sale_del_clasificador(self):
        self.assertNotIn("JOYERIA", mapeo.TIPOS)

    def test_sin_atributo_de_patron_no_es_liso(self):
        self.assertIsNone(mapeo.patron_de_atributos(["symmetrical", "no waistline"]))

    def test_patron_unico_y_contradictorio(self):
        self.assertEqual(mapeo.patron_de_atributos(["plain (pattern)"]), "LISO")
        self.assertEqual(mapeo.patron_de_atributos(["leopard", "cheetah"]), "ANIMAL")
        self.assertIsNone(mapeo.patron_de_atributos(["stripe", "floral"]))

    def test_licencias_no_comerciales_no_entrenan(self):
        for nombre in (
            "Attribution-NonCommercial-NoDerivatives License",
            "Attribution-NonCommercial-ShareAlike License",
            "Attribution-NonCommercial License",
            "all rights reserved/not found",
        ):
            self.assertFalse(mapeo.licencia_admitida(nombre), nombre)
        for nombre in ("Attribution License", "Attribution-NoDerivatives License", "CC0 1.0", "unsplash", "pexels"):
            self.assertTrue(mapeo.licencia_admitida(nombre), nombre)

    def test_ontologia_con_categoria_nueva(self):
        categorias = [*mapeo.TIPO_DESDE_FASHIONPEDIA, *mapeo.DESCARTADAS_FASHIONPEDIA, "poncho"]
        problemas = mapeo.comprobar_ontologia(categorias, list(mapeo.PATRON_DESDE_FASHIONPEDIA))
        self.assertEqual(problemas, ["categoria sin mapear ni descartar: 'poncho'"])


class TestConfiguracion(unittest.TestCase):
    def test_salida_dentro_de_un_repositorio_se_rechaza(self):
        with tempfile.TemporaryDirectory() as tmp:
            raiz = Path(tmp)
            repo = raiz / "repo"
            (repo / ".git").mkdir(parents=True)
            ruta = raiz / "prendas.json"
            ruta.write_text(json.dumps({"datos": str(raiz / "datos"), "salida": str(repo / "x")}))
            with self.assertRaisesRegex(configuracion.ErrorDeConfiguracion, "salida"):
                configuracion.cargar(ruta)


if __name__ == "__main__":
    unittest.main()
