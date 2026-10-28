"""Paso 3: entrena el clasificador de dos cabezas en GPU.

    python tools/entrenamiento/prendas/entrenar.py [--epocas 15]

- Perdida = entropia cruzada de tipo + entropia cruzada de patron. Las imagenes
  sin etiqueta de patron (Grigorev, accesorios) no aportan a la segunda.
- Pesos de clase por la raiz inversa de la frecuencia: los patrones raros
  (animal, puntos) no desaparecen bajo el liso.
- Se queda con la epoca de mejor exactitud media de las dos cabezas en validacion.
- Solo entrenan imagenes de licencia comercial (`mapeo.licencia_admitida`): el
  dataset se construye entero y el filtro se aplica aqui, sin reconstruirlo.

Escribe `<salida>/modelo/pesos.pt`, `etiquetas.json` y `entrenamiento.json`.
"""

from __future__ import annotations

import argparse
import csv
import json
import random
import sys
import time
from pathlib import Path

import numpy as np
import torch
from PIL import Image
from torch import nn
from torch.utils.data import DataLoader, Dataset

sys.path.insert(0, str(Path(__file__).resolve().parent))

import configuracion  # noqa: E402
from mapeo import LICENCIAS_EXCLUIDAS, PATRONES, TIPOS, licencia_admitida  # noqa: E402
from modelo import ENTRADA, ClasificadorPrenda, etiquetas  # noqa: E402

SEMILLA = 42
SIN_ETIQUETA = -1


def a_cuadrado(im: Image.Image, fondo=(255, 255, 255)) -> Image.Image:
    """Rellena a cuadrado y escala a la entrada. Es el preproceso del telefono."""
    lado = max(im.size)
    lienzo = Image.new("RGB", (lado, lado), fondo)
    lienzo.paste(im, ((lado - im.width) // 2, (lado - im.height) // 2))
    return lienzo.resize((ENTRADA, ENTRADA), Image.Resampling.BILINEAR)


def leer_manifiesto(rutas: configuracion.Rutas, particion: str) -> list[dict]:
    """Filas de una particion. En train y val solo las de licencia admitida.

    La prueba se queda entera: medir no mete esas imagenes en los pesos, y con
    el filtro varias clases se quedarian en un punado de casos.
    """
    with (rutas.dataset / "manifiesto.csv").open(newline="", encoding="utf-8") as f:
        filas = [r for r in csv.DictReader(f) if r["particion"] == particion]
    if particion == "test":
        return filas
    return [r for r in filas if licencia_admitida(r["licencia"])]


class Recortes(Dataset):
    def __init__(self, carpeta: Path, filas: list[dict], aumentar: bool) -> None:
        self.carpeta = carpeta
        self.filas = filas
        self.aumentar = aumentar

    def __len__(self) -> int:
        return len(self.filas)

    def __getitem__(self, i: int):
        fila = self.filas[i]
        im = Image.open(self.carpeta / fila["archivo"]).convert("RGB")
        if self.aumentar:
            im = self._aumentar(im, fila)
        im = a_cuadrado(im)
        x = torch.from_numpy(np.asarray(im, dtype=np.float32).copy()).permute(2, 0, 1)
        tipo = TIPOS.index(fila["tipo"])
        patron = PATRONES.index(fila["patron"]) if fila["patron"] else SIN_ETIQUETA
        return x, tipo, patron

    def _aumentar(self, im: Image.Image, fila: dict) -> Image.Image:
        if random.random() < 0.5:
            im = im.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        # Recorte aleatorio suave: la prenda casi entera, como en la app.
        escala = random.uniform(0.85, 1.0)
        w, h = round(im.width * escala), round(im.height * escala)
        x0, y0 = random.randint(0, im.width - w), random.randint(0, im.height - h)
        im = im.crop((x0, y0, x0 + w, y0 + h))
        a = np.asarray(im, dtype=np.float32)
        # Fondo de otro color en los recortes con mascara: el fondo que deje
        # u2netp en la app no tiene por que ser blanco.
        if fila["fuente"] == "fashionpedia" and random.random() < 0.3:
            blanco = (a >= 250).all(axis=2)
            a[blanco] = np.random.uniform(0, 255, 3)
        # Brillo y contraste leves; el color no define ni el tipo ni el patron.
        a = (a - 128) * random.uniform(0.8, 1.2) + 128 + random.uniform(-20, 20)
        return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def pesos_de_clase(valores: list[int], n: int) -> torch.Tensor:
    conteo = np.bincount([v for v in valores if v >= 0], minlength=n).astype(float)
    pesos = 1 / np.sqrt(np.maximum(conteo, 1))
    return torch.tensor(pesos / pesos.mean(), dtype=torch.float32)


@torch.no_grad()
def predecir(modelo: nn.Module, cargador: DataLoader, dispositivo) -> dict[str, np.ndarray]:
    modelo.eval()
    salida = {"tipo": [], "patron": [], "tipo_real": [], "patron_real": []}
    for x, tipo, patron in cargador:
        logits_tipo, logits_patron = modelo(x.to(dispositivo))
        salida["tipo"].append(logits_tipo.argmax(1).cpu().numpy())
        salida["patron"].append(logits_patron.argmax(1).cpu().numpy())
        salida["tipo_real"].append(tipo.numpy())
        salida["patron_real"].append(patron.numpy())
    return {k: np.concatenate(v) for k, v in salida.items()}


def exactitudes(p: dict[str, np.ndarray]) -> dict[str, float]:
    con_patron = p["patron_real"] >= 0
    return {
        "tipo": float(np.mean(p["tipo"] == p["tipo_real"])),
        "patron": float(np.mean(p["patron"][con_patron] == p["patron_real"][con_patron])),
        "n_tipo": int(len(p["tipo_real"])),
        "n_patron": int(con_patron.sum()),
    }


def principal(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--epocas", type=int, default=15)
    parser.add_argument("--lote", type=int, default=128)
    parser.add_argument("--procesos", type=int, default=4)
    args = parser.parse_args(argv)

    random.seed(SEMILLA)
    np.random.seed(SEMILLA)
    torch.manual_seed(SEMILLA)

    rutas = configuracion.cargar()
    carpeta = rutas.dataset / "imagenes"
    salida = rutas.salida / "modelo"
    salida.mkdir(parents=True, exist_ok=True)
    dispositivo = torch.device("cuda" if torch.cuda.is_available() else "cpu")

    train = leer_manifiesto(rutas, "train")
    val = leer_manifiesto(rutas, "val")
    cargar = lambda filas, aumentar: DataLoader(  # noqa: E731
        Recortes(carpeta, filas, aumentar),
        batch_size=args.lote,
        shuffle=aumentar,
        num_workers=args.procesos,
        persistent_workers=args.procesos > 0,
        pin_memory=True,
    )
    cargador_train, cargador_val = cargar(train, True), cargar(val, False)

    modelo = ClasificadorPrenda().to(dispositivo)
    criterio_tipo = nn.CrossEntropyLoss(
        weight=pesos_de_clase([TIPOS.index(f["tipo"]) for f in train], len(TIPOS)).to(dispositivo),
        label_smoothing=0.05,
    )
    criterio_patron = nn.CrossEntropyLoss(
        weight=pesos_de_clase(
            [PATRONES.index(f["patron"]) for f in train if f["patron"]], len(PATRONES)
        ).to(dispositivo),
        ignore_index=SIN_ETIQUETA,
        label_smoothing=0.05,
    )
    optimizador = torch.optim.AdamW(modelo.parameters(), lr=1e-3, weight_decay=0.02)
    pasos = args.epocas * len(cargador_train)
    planificador = torch.optim.lr_scheduler.OneCycleLR(optimizador, max_lr=1e-3, total_steps=pasos, pct_start=0.1)
    escalador = torch.amp.GradScaler("cuda", enabled=dispositivo.type == "cuda")

    historial, mejor = [], -1.0
    for epoca in range(1, args.epocas + 1):
        modelo.train()
        inicio, perdida_total = time.monotonic(), 0.0
        for x, tipo, patron in cargador_train:
            x, tipo, patron = x.to(dispositivo), tipo.to(dispositivo), patron.to(dispositivo)
            with torch.autocast(dispositivo.type, enabled=dispositivo.type == "cuda"):
                logits_tipo, logits_patron = modelo(x)
                perdida = criterio_tipo(logits_tipo, tipo)
                if (patron >= 0).any():
                    perdida = perdida + criterio_patron(logits_patron, patron)
            optimizador.zero_grad(set_to_none=True)
            escalador.scale(perdida).backward()
            escalador.step(optimizador)
            escalador.update()
            planificador.step()
            perdida_total += perdida.item() * len(x)

        metricas = exactitudes(predecir(modelo, cargador_val, dispositivo))
        puntuacion = (metricas["tipo"] + metricas["patron"]) / 2
        historial.append({"epoca": epoca, "perdida": perdida_total / len(train), **metricas})
        print(
            f"epoca {epoca}: perdida {perdida_total / len(train):.3f}  val tipo {metricas['tipo']:.3f}"
            f"  patron {metricas['patron']:.3f}  {time.monotonic() - inicio:.0f}s",
            flush=True,
        )
        if puntuacion > mejor:
            mejor = puntuacion
            torch.save(modelo.state_dict(), salida / "pesos.pt")

    (salida / "etiquetas.json").write_text(json.dumps(etiquetas(), indent=2), encoding="utf-8")
    (salida / "entrenamiento.json").write_text(
        json.dumps(
            {
                "semilla": SEMILLA,
                "args": vars(args),
                "licencias_excluidas": list(LICENCIAS_EXCLUIDAS),
                "recortes": {"train": len(train), "val": len(val)},
                "historial": historial,
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    sys.exit(principal())
