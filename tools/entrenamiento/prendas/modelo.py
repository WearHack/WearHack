"""El clasificador de prendas: MobileNetV3-Small con dos cabezas (tipo y patron).

Lo comparten `entrenar`, `exportar` y `evaluar`, para que el modelo que se
exporta sea exactamente el que se entreno.

La normalizacion va dentro del modelo: el telefono le pasa pixeles RGB en
[0, 255] y no tiene que saber que media y desviacion uso el entrenamiento.
"""

from __future__ import annotations

import timm
import torch
from torch import nn

from mapeo import PATRONES, TIPOS

ENTRADA = 224
ARQUITECTURA = "mobilenetv3_small_100"
# Pesos preentrenados en ImageNet que publica timm (ver la procedencia).
PREENTRENADO = "mobilenetv3_small_100.lamb_in1k"
MEDIA = (0.485, 0.456, 0.406)
DESVIACION = (0.229, 0.224, 0.225)


class ClasificadorPrenda(nn.Module):
    def __init__(self, preentrenado: bool = True) -> None:
        super().__init__()
        self.base = timm.create_model(
            PREENTRENADO if preentrenado else ARQUITECTURA, pretrained=preentrenado, num_classes=0
        )
        # Sin clasificador, MobileNetV3 sale por conv_head (1024), no por num_features (576).
        caracteristicas = self.base.head_hidden_size
        self.tipo = nn.Sequential(nn.Dropout(0.2), nn.Linear(caracteristicas, len(TIPOS)))
        self.patron = nn.Sequential(nn.Dropout(0.2), nn.Linear(caracteristicas, len(PATRONES)))
        self.register_buffer("media", torch.tensor(MEDIA).view(1, 3, 1, 1) * 255)
        self.register_buffer("desviacion", torch.tensor(DESVIACION).view(1, 3, 1, 1) * 255)

    def forward(self, x: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
        """`x`: (n, 3, 224, 224) RGB en [0, 255]. Devuelve logits de tipo y de patron."""
        f = self.base((x - self.media) / self.desviacion)
        return self.tipo(f), self.patron(f)


class EntradaNHWC(nn.Module):
    """Lo que se exporta: el telefono entrega la imagen como (n, 224, 224, 3)."""

    def __init__(self, modelo: ClasificadorPrenda) -> None:
        super().__init__()
        self.modelo = modelo

    def forward(self, x: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
        return self.modelo(x.permute(0, 3, 1, 2))


def cargar_entrenado(ruta_pesos) -> ClasificadorPrenda:
    """El modelo con los pesos de `entrenar`, en modo evaluacion y en CPU."""
    modelo = ClasificadorPrenda(preentrenado=False)
    modelo.load_state_dict(torch.load(ruta_pesos, map_location="cpu", weights_only=True))
    return modelo.eval()


def etiquetas() -> dict:
    """Lo que el cliente necesita para interpretar las salidas."""
    return {
        "entrada": {
            "forma": [1, ENTRADA, ENTRADA, 3],
            "canales": "RGB",
            "rango": [0, 255],
            "preproceso": "rellenar a cuadrado con blanco y escalar a 224 bilineal",
        },
        "salidas": {"tipo": list(TIPOS), "patron": list(PATRONES)},
    }
