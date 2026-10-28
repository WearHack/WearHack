"""Paso 4: exporta el clasificador a LiteRT. Corre en WSL, no en Windows.

    WEARHACK_PRENDAS_CONFIG=<config con rutas /mnt/c/...> \\
        python tools/entrenamiento/prendas/exportar.py [--por-tensor]

`litert-torch` (antes ai-edge-torch) no publica ruedas para Windows. Escribe en
`<salida>/modelo/` tres variantes, para que `evaluar` elija:

- `clasificador_prenda_fp32.tflite`: la referencia. Separa el error de la
  conversion del error de la cuantizacion.
- `clasificador_prenda_int8.tflite`: PT2E estatico, pesos y activaciones en
  INT8, calibrado con recortes de entrenamiento. Por canal salvo `--por-tensor`.
- `clasificador_prenda_fp16.tflite`: pesos en FP16, computo en float. El plan B
  si INT8 pierde mas de un punto en alguna cabeza.

La entrada es (1, 224, 224, 3) RGB en [0, 255]: la normalizacion va dentro.
"""

from __future__ import annotations

import argparse
import importlib.metadata
import json
import random
import sys
from pathlib import Path

import numpy as np
import torch
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))

import configuracion  # noqa: E402
from entrenar import a_cuadrado, leer_manifiesto  # noqa: E402
from modelo import ENTRADA, EntradaNHWC, cargar_entrenado  # noqa: E402

SEMILLA = 42
# Recortes de calibracion por tipo: cubre todas las clases sin sesgarse al calzado.
CALIBRACION_POR_TIPO = 25
NOMBRE = "clasificador_prenda_{}.tflite"
PAQUETES = ("litert-torch", "ai-edge-litert", "ai-edge-quantizer", "torch", "torchao", "timm", "numpy")


def lote_nhwc(carpeta: Path, fila: dict) -> torch.Tensor:
    im = a_cuadrado(Image.open(carpeta / fila["archivo"]).convert("RGB"))
    return torch.from_numpy(np.asarray(im, dtype=np.float32).copy()).unsqueeze(0)


def muestras_de_calibracion(rutas: configuracion.Rutas) -> list[torch.Tensor]:
    por_tipo: dict[str, list[dict]] = {}
    for fila in leer_manifiesto(rutas, "train"):
        por_tipo.setdefault(fila["tipo"], []).append(fila)
    rng = random.Random(SEMILLA)
    elegidas = []
    for tipo in sorted(por_tipo):
        elegidas += rng.sample(por_tipo[tipo], min(CALIBRACION_POR_TIPO, len(por_tipo[tipo])))
    carpeta = rutas.dataset / "imagenes"
    return [lote_nhwc(carpeta, f) for f in elegidas]


def exportar_fp32(modelo: torch.nn.Module, ejemplo: tuple, destino: Path) -> None:
    import litert_torch

    litert_torch.convert(modelo, ejemplo).export(str(destino))


def exportar_int8(
    modelo: torch.nn.Module, ejemplo: tuple, calibracion: list[torch.Tensor], por_canal: bool, destino: Path
) -> None:
    import litert_torch
    from litert_torch.quantize import pt2e_quantizer
    from litert_torch.quantize.quant_config import QuantConfig
    from torchao.quantization.pt2e import quantize_pt2e

    cuantizador = pt2e_quantizer.PT2EQuantizer().set_global(
        pt2e_quantizer.get_symmetric_quantization_config(is_per_channel=por_canal, is_dynamic=False)
    )
    m = torch.export.export(modelo, ejemplo).module()
    m = quantize_pt2e.prepare_pt2e(m, cuantizador)
    with torch.no_grad():
        for x in calibracion:
            m(x)
    m = quantize_pt2e.convert_pt2e(m, fold_quantize=False)
    convertido = litert_torch.convert(m, ejemplo, quant_config=QuantConfig(pt2e_quantizer=cuantizador))
    convertido.export(str(destino))


def exportar_fp16(origen_fp32: Path, destino: Path) -> None:
    """Pesos en FP16 sobre el modelo float ya convertido (float casting)."""
    from ai_edge_quantizer import Quantizer, qtyping

    q = Quantizer(str(origen_fp32))
    # Solo estas operaciones admiten float casting; el resto queda en FP32.
    for operacion in ("CONV_2D", "DEPTHWISE_CONV_2D", "FULLY_CONNECTED"):
        q.add_weight_only_config(
            regex=".*",
            operation_name=qtyping.TFLOperationName[operacion],
            num_bits=16,
            algorithm_key="float_casting",
        )
    q.quantize().export_model(str(destino), overwrite=True)


def principal(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--por-tensor", action="store_true", help="INT8 por tensor en vez de por canal (peor, solo para comparar)"
    )
    args = parser.parse_args(argv)
    torch.manual_seed(SEMILLA)

    rutas = configuracion.cargar()
    carpeta = rutas.salida / "modelo"
    modelo = EntradaNHWC(cargar_entrenado(carpeta / "pesos.pt")).eval()
    ejemplo = (torch.zeros(1, ENTRADA, ENTRADA, 3),)

    fp32 = carpeta / NOMBRE.format("fp32")
    print("Exportando FP32...", flush=True)
    exportar_fp32(modelo, ejemplo, fp32)

    print("Calibrando y exportando INT8...", flush=True)
    calibracion = muestras_de_calibracion(rutas)
    exportar_int8(modelo, ejemplo, calibracion, not args.por_tensor, carpeta / NOMBRE.format("int8"))

    print("Exportando FP16...", flush=True)
    exportar_fp16(fp32, carpeta / NOMBRE.format("fp16"))

    (carpeta / "exportacion.json").write_text(
        json.dumps(
            {
                "semilla": SEMILLA,
                "versiones": {p: importlib.metadata.version(p) for p in PAQUETES},
                "int8": "por tensor" if args.por_tensor else "por canal",
                "recortes_de_calibracion": len(calibracion),
                "variantes": {
                    v: (carpeta / NOMBRE.format(v)).stat().st_size for v in ("fp32", "int8", "fp16")
                },
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    print(f"Listo en {carpeta}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(principal())
