"""Paso 5: compara el modelo PyTorch (FP32) con cada .tflite exportado. En WSL.

    WEARHACK_PRENDAS_CONFIG=<config con rutas /mnt/c/...> \\
        python tools/entrenamiento/prendas/evaluar.py

Para cada variante y para validacion y prueba: exactitud de cada cabeza, caida
en puntos frente a PyTorch, exactitud por fuente y recall por clase. Tambien
tamano frente al presupuesto y latencia en la CPU del PC (un hilo).

Criterio de #69: INT8 vale si **ninguna** cabeza cae mas de 1 punto en prueba.
Si no, la recomendada es FP16. Escribe `<salida>/modelo/evaluacion.json` e
`informe.md`.
"""

from __future__ import annotations

import collections
import json
import statistics
import sys
import time
from pathlib import Path

import numpy as np
import torch
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))

import configuracion  # noqa: E402
from entrenar import a_cuadrado, leer_manifiesto  # noqa: E402
from exportar import NOMBRE  # noqa: E402
from mapeo import PATRONES, TIPOS  # noqa: E402
from modelo import EntradaNHWC, cargar_entrenado  # noqa: E402

VARIANTES = ("fp32", "int8", "fp16")
CAIDA_MAXIMA = 1.0  # puntos porcentuales por cabeza
PRESUPUESTO_MB = 15.0
REPETICIONES_LATENCIA = 50


class Tflite:
    """Un interprete de LiteRT con las dos salidas identificadas por su tamano."""

    def __init__(self, ruta: Path, hilos: int = 4) -> None:
        from ai_edge_litert.interpreter import Interpreter

        self.ruta = ruta
        self.interprete = Interpreter(model_path=str(ruta), num_threads=hilos)
        self.interprete.allocate_tensors()
        self.entrada = self.interprete.get_input_details()[0]
        salidas = self.interprete.get_output_details()
        por_tamano = {int(s["shape"][-1]): s for s in salidas}
        self.salida_tipo, self.salida_patron = por_tamano[len(TIPOS)], por_tamano[len(PATRONES)]

    def __call__(self, x: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        self.interprete.set_tensor(self.entrada["index"], _cuantizar(x, self.entrada))
        self.interprete.invoke()
        return (
            _decuantizar(self.interprete.get_tensor(self.salida_tipo["index"]), self.salida_tipo),
            _decuantizar(self.interprete.get_tensor(self.salida_patron["index"]), self.salida_patron),
        )


def _cuantizar(x: np.ndarray, detalle: dict) -> np.ndarray:
    if detalle["dtype"] == np.float32:
        return x
    escala, cero = detalle["quantization"]
    info = np.iinfo(detalle["dtype"])
    return np.clip(np.round(x / escala + cero), info.min, info.max).astype(detalle["dtype"])


def _decuantizar(y: np.ndarray, detalle: dict) -> np.ndarray:
    if detalle["dtype"] == np.float32:
        return y
    escala, cero = detalle["quantization"]
    return (y.astype(np.float32) - cero) * escala


def predecir(rutas: configuracion.Rutas, particion: str, modelos: dict) -> list[dict]:
    """Una fila por recorte con la prediccion de cada modelo."""
    carpeta = rutas.dataset / "imagenes"
    filas = leer_manifiesto(rutas, particion)
    resultado = []
    for i, fila in enumerate(filas, 1):
        im = a_cuadrado(Image.open(carpeta / fila["archivo"]).convert("RGB"))
        x = np.asarray(im, dtype=np.float32)[None]
        prediccion = {}
        for nombre, modelo in modelos.items():
            tipo, patron = modelo(x)
            prediccion[nombre] = (int(np.argmax(tipo)), int(np.argmax(patron)))
        resultado.append({"fila": fila, "prediccion": prediccion})
        if i % 1000 == 0:
            print(f"  {particion}: {i}/{len(filas)}", flush=True)
    return resultado


def metricas(resultado: list[dict], nombre: str) -> dict:
    aciertos = {"tipo": [], "patron": []}
    por_fuente = collections.defaultdict(lambda: {"tipo": [], "patron": []})
    por_clase = {"tipo": collections.defaultdict(list), "patron": collections.defaultdict(list)}
    for r in resultado:
        fila, (tipo, patron) = r["fila"], r["prediccion"][nombre]
        bien = tipo == TIPOS.index(fila["tipo"])
        aciertos["tipo"].append(bien)
        por_fuente[fila["fuente"]]["tipo"].append(bien)
        por_clase["tipo"][fila["tipo"]].append(bien)
        if fila["patron"]:
            bien = patron == PATRONES.index(fila["patron"])
            aciertos["patron"].append(bien)
            por_fuente[fila["fuente"]]["patron"].append(bien)
            por_clase["patron"][fila["patron"]].append(bien)

    def pct(v: list[bool]) -> float | None:
        return round(100 * float(np.mean(v)), 2) if v else None

    return {
        "tipo": pct(aciertos["tipo"]),
        "patron": pct(aciertos["patron"]),
        "n_tipo": len(aciertos["tipo"]),
        "n_patron": len(aciertos["patron"]),
        "por_fuente": {f: {c: pct(v) for c, v in d.items()} for f, d in sorted(por_fuente.items())},
        "recall_por_clase": {
            c: {k: {"recall": pct(v), "n": len(v)} for k, v in sorted(d.items())} for c, d in por_clase.items()
        },
    }


def latencia_ms(ruta: Path) -> float:
    modelo = Tflite(ruta, hilos=1)
    x = np.random.default_rng(0).uniform(0, 255, (1, 224, 224, 3)).astype(np.float32)
    for _ in range(5):
        modelo(x)
    tiempos = []
    for _ in range(REPETICIONES_LATENCIA):
        inicio = time.perf_counter()
        modelo(x)
        tiempos.append(1000 * (time.perf_counter() - inicio))
    return round(statistics.median(tiempos), 2)


def informe(evaluacion: dict) -> str:
    lineas = [
        "# Clasificador de prendas: PyTorch frente a LiteRT",
        "",
        (
            f"Criterio: ninguna cabeza cae mas de {CAIDA_MAXIMA} punto en prueba. "
            f"Recomendada: **{evaluacion['recomendada']}**."
        ),
        "",
        "| Variante | Particion | Tipo % | Patron % | Caida tipo | Caida patron | MB | ms (1 hilo) |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for nombre, v in evaluacion["variantes"].items():
        for particion in ("val", "test"):
            m = v[particion]
            lineas.append(
                f"| {nombre} | {particion} | {m['tipo']} | {m['patron']} | {m.get('caida_tipo', '-')} "
                f"| {m.get('caida_patron', '-')} | {v.get('mb', '-')} | {v.get('latencia_ms', '-')} |"
            )
    referencia = evaluacion["variantes"]["pytorch"]["test"]["recall_por_clase"]
    for cabeza in ("tipo", "patron"):
        lineas += ["", f"## Recall por clase de {cabeza} (prueba, PyTorch)", "", "| Clase | Recall % | n |", "|---|---|---|"]
        lineas += [f"| {c} | {d['recall']} | {d['n']} |" for c, d in referencia[cabeza].items()]
    return "\n".join(lineas) + "\n"


def principal() -> int:
    rutas = configuracion.cargar()
    carpeta = rutas.salida / "modelo"
    pytorch = EntradaNHWC(cargar_entrenado(carpeta / "pesos.pt"))

    @torch.no_grad()
    def referencia(x: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        tipo, patron = pytorch(torch.from_numpy(x))
        return tipo.numpy(), patron.numpy()

    modelos = {"pytorch": referencia}
    for v in VARIANTES:
        ruta = carpeta / NOMBRE.format(v)
        if ruta.exists():
            modelos[v] = Tflite(ruta)
        else:
            print(f"Falta {ruta.name}; se evalua sin ella.", flush=True)

    evaluacion: dict = {"variantes": {n: {} for n in modelos}}
    for particion in ("val", "test"):
        resultado = predecir(rutas, particion, modelos)
        for nombre in modelos:
            evaluacion["variantes"][nombre][particion] = metricas(resultado, nombre)
    for nombre, v in evaluacion["variantes"].items():
        if nombre == "pytorch":
            continue
        for particion in ("val", "test"):
            base = evaluacion["variantes"]["pytorch"][particion]
            for cabeza in ("tipo", "patron"):
                v[particion][f"caida_{cabeza}"] = round(base[cabeza] - v[particion][cabeza], 2)
        ruta = carpeta / NOMBRE.format(nombre)
        v["mb"] = round(ruta.stat().st_size / 2**20, 2)
        v["dentro_del_presupuesto"] = v["mb"] <= PRESUPUESTO_MB
        v["latencia_ms"] = latencia_ms(ruta)

    int8 = evaluacion["variantes"].get("int8", {}).get("test")
    cumple = int8 is not None and max(int8["caida_tipo"], int8["caida_patron"]) <= CAIDA_MAXIMA
    evaluacion["int8_cumple"] = cumple
    evaluacion["recomendada"] = "int8" if cumple else "fp16"

    (carpeta / "evaluacion.json").write_text(json.dumps(evaluacion, indent=2), encoding="utf-8")
    (carpeta / "informe.md").write_text(informe(evaluacion), encoding="utf-8")
    print(informe(evaluacion))
    return 0


if __name__ == "__main__":
    sys.exit(principal())
