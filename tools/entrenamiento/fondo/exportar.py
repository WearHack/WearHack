"""Exporta u2netp a LiteRT para quitar el fondo en el telefono. Corre en WSL.

    python tools/entrenamiento/fondo/exportar.py --pesos <u2netp.pth> --salida <carpeta>

Usa el mismo venv que el clasificador (`requirements-exportacion.txt` de
`../prendas/`): `litert-torch` no publica ruedas para Windows.

Los pesos son los oficiales de U^2-Net (`u2netp.pth`, 4,7 MB, Apache 2.0). No se
reentrena nada: ver `docs/respuestas-claude-code.md`, punto 19.

Escribe `u2netp_fp32.tflite` y `u2netp_fp16.tflite` (pesos en FP16, computo en
float, como el clasificador), mas `exportacion.json` con el error de cada
variante frente a PyTorch. INT8 no se intenta: en el clasificador perdio 30
puntos sin QAT y aqui no hay datos para calibrar ni para medir.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import sys
from pathlib import Path

import numpy as np
import torch

sys.path.insert(0, str(Path(__file__).resolve().parent))

from modelo_u2netp import ENTRADA, EntradaNHWC, cargar_oficial  # noqa: E402

SEMILLA = 42
PAQUETES = ("litert-torch", "ai-edge-litert", "ai-edge-quantizer", "torch", "numpy")


def imagen_sintetica() -> torch.Tensor:
    """Fondo gris claro con una "prenda" roja en el centro. Para medir el error
    de la conversion y comprobar que la mascara tiene sentido."""
    x = np.full((ENTRADA, ENTRADA, 3), 225.0, dtype=np.float32)
    x[80:240, 100:220] = (170.0, 30.0, 40.0)
    return torch.from_numpy(x).unsqueeze(0)


def exportar_fp16(origen_fp32: Path, destino: Path) -> None:
    from ai_edge_quantizer import Quantizer, qtyping

    q = Quantizer(str(origen_fp32))
    for operacion in ("CONV_2D", "DEPTHWISE_CONV_2D", "FULLY_CONNECTED"):
        q.add_weight_only_config(
            regex=".*",
            operation_name=qtyping.TFLOperationName[operacion],
            num_bits=16,
            algorithm_key="float_casting",
        )
    q.quantize().export_model(str(destino), overwrite=True)


def inferir_tflite(ruta: Path, x: np.ndarray) -> np.ndarray:
    from ai_edge_litert.interpreter import Interpreter

    interprete = Interpreter(model_path=str(ruta))
    interprete.allocate_tensors()
    entrada = interprete.get_input_details()[0]
    interprete.set_tensor(entrada["index"], x)
    interprete.invoke()
    return interprete.get_tensor(interprete.get_output_details()[0]["index"])


def principal(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--pesos", type=Path, required=True, help="u2netp.pth oficial")
    parser.add_argument("--salida", type=Path, required=True)
    args = parser.parse_args(argv)
    torch.manual_seed(SEMILLA)
    args.salida.mkdir(parents=True, exist_ok=True)

    modelo = EntradaNHWC(cargar_oficial(str(args.pesos))).eval()
    print("Pesos cargados en modo estricto.", flush=True)
    ejemplo = (torch.zeros(1, ENTRADA, ENTRADA, 3),)

    import litert_torch

    fp32 = args.salida / "u2netp_fp32.tflite"
    fp16 = args.salida / "u2netp_fp16.tflite"
    print("Exportando FP32...", flush=True)
    litert_torch.convert(modelo, ejemplo).export(str(fp32))
    print("Exportando FP16...", flush=True)
    exportar_fp16(fp32, fp16)

    x = imagen_sintetica()
    with torch.no_grad():
        referencia = modelo(x).numpy()
    prenda = np.zeros((ENTRADA, ENTRADA), dtype=bool)
    prenda[80:240, 100:220] = True

    informe: dict = {
        "pesos_sha256": hashlib.sha256(args.pesos.read_bytes()).hexdigest(),
        "entrada": [1, ENTRADA, ENTRADA, 3],
        "versiones": {p: importlib.metadata.version(p) for p in PAQUETES},
        "pytorch_media_dentro_fuera": [float(referencia[0, prenda, 0].mean()), float(referencia[0, ~prenda, 0].mean())],
        "variantes": {},
    }
    for ruta in (fp32, fp16):
        salida = inferir_tflite(ruta, x.numpy())
        informe["variantes"][ruta.name] = {
            "bytes": ruta.stat().st_size,
            "sha256": hashlib.sha256(ruta.read_bytes()).hexdigest(),
            "forma_salida": list(salida.shape),
            "error_max_vs_pytorch": float(np.abs(salida - referencia).max()),
        }

    (args.salida / "exportacion.json").write_text(json.dumps(informe, indent=2), encoding="utf-8")
    print(json.dumps(informe, indent=2), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(principal())
