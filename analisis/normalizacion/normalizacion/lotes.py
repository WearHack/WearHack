"""Las tomas de la sesion de calibracion, leidas de la boveda.

`tools/captura/importar_lote.py` deja cada lote en una carpeta de la boveda con,
por toma, `P3_LEDC_D2_R1_G.json`, `..._foto.jpg` y `..._recorte.png`. Aqui se
recorren esas carpetas y se valida cada JSON con el mismo codigo que lo importo.

D3 (el Android de gama media) queda fuera por defecto: es el celular reservado
para la validacion final (protocolo, seccion 7).
"""

import json
from dataclasses import dataclass
from pathlib import Path

import importar_lote

LUCES_NORMALES = ("VEN", "LEDC", "LEDF")
CELULAR_RESERVADO = "D3"


@dataclass(frozen=True)
class Toma:
    id: str  # P3_LEDC_D2_R1_G
    seudonimo: str
    luz: str
    celular: str
    repeticion: str
    tarjeta: bool
    foto: Path
    recorte: Path
    ancho_rostro: int = 0  # en pixeles de la foto completa, segun la app

    @property
    def luz_normal(self) -> bool:
        return self.luz in LUCES_NORMALES


@dataclass
class Carga:
    tomas: list[Toma]
    problemas: list[str]
    excluidas_d3: int = 0


def cargar(raiz: Path, incluir_d3: bool = False) -> Carga:
    """Todas las tomas validas bajo `raiz`. Lo que no cuadra va a `problemas`."""
    tomas: dict[str, Toma] = {}
    problemas: list[str] = []
    excluidas = 0
    for ruta in sorted(raiz.rglob("*.json")):
        nombre = importar_lote.NOMBRE_ARCHIVO.fullmatch(ruta.name)
        if not nombre or nombre["resto"] != ".json":
            continue  # manifiestos y otros JSON
        base = nombre["base"]
        try:
            datos = json.loads(ruta.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as e:
            problemas.append(f"{ruta}: no se pudo leer ({e})")
            continue
        errores = importar_lote.validar_metadatos(datos)
        if errores:
            problemas.append(f"{ruta}: " + "; ".join(errores))
            continue
        foto = ruta.with_name(datos["archivos"]["foto"])
        recorte = ruta.with_name(datos["archivos"]["recorte"])
        if not foto.is_file() or not recorte.is_file():
            problemas.append(f"{ruta}: falta la foto o el recorte")
            continue
        if base in tomas:
            problemas.append(f"{base} aparece en dos lotes; se usa {tomas[base].foto.parent}")
            continue
        toma = Toma(
            id=base,
            seudonimo=datos["seudonimo"],
            luz=datos["luz"],
            celular=datos["celular"]["codigo"],
            repeticion=datos["repeticion"],
            tarjeta=datos["tarjeta_gris"],
            foto=foto,
            recorte=recorte,
            ancho_rostro=datos["rostro"]["ancho_px"],
        )
        if toma.celular == CELULAR_RESERVADO and not incluir_d3:
            excluidas += 1
            continue
        tomas[base] = toma
    return Carga(
        tomas=sorted(tomas.values(), key=lambda t: t.id), problemas=problemas, excluidas_d3=excluidas
    )
