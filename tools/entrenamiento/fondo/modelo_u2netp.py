"""U^2-Net ligero (u2netp) para quitar el fondo de una prenda.

Es la arquitectura de Qin et al. (2020), reescrita a partir del articulo y del
repositorio oficial (Apache 2.0) para no vendorizar su codigo. Los nombres de
las capas son los del original: asi `load_state_dict(strict=True)` carga los
pesos oficiales `u2netp.pth` y falla si alguna capa no coincide.

`EntradaNHWC` envuelve la red con lo que el telefono necesita: entrada NHWC RGB
en [0, 255], la normalizacion de ImageNet dentro, y solo la mascara final d0.
"""

from __future__ import annotations

import torch
import torch.nn.functional as F
from torch import nn

ENTRADA = 320
MEDIA = (0.485, 0.456, 0.406)
DESVIACION = (0.229, 0.224, 0.225)


class REBNCONV(nn.Module):
    def __init__(self, entrada: int, salida: int, dilatacion: int = 1) -> None:
        super().__init__()
        self.conv_s1 = nn.Conv2d(entrada, salida, 3, padding=dilatacion, dilation=dilatacion)
        self.bn_s1 = nn.BatchNorm2d(salida)
        self.relu_s1 = nn.ReLU(inplace=True)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.relu_s1(self.bn_s1(self.conv_s1(x)))


def _como(src: torch.Tensor, ref: torch.Tensor) -> torch.Tensor:
    return F.interpolate(src, size=ref.shape[2:], mode="bilinear", align_corners=False)


class RSU(nn.Module):
    """RSU-L: un U-Net de `niveles` capas dentro de un bloque residual.

    Equivale a RSU7, RSU6, RSU5 y RSU4 del original con niveles 7, 6, 5 y 4.
    """

    def __init__(self, niveles: int, entrada: int, medio: int, salida: int) -> None:
        super().__init__()
        self.niveles = niveles
        self.rebnconvin = REBNCONV(entrada, salida)
        self.rebnconv1 = REBNCONV(salida, medio)
        for i in range(2, niveles):
            setattr(self, f"rebnconv{i}", REBNCONV(medio, medio))
        setattr(self, f"rebnconv{niveles}", REBNCONV(medio, medio, dilatacion=2))
        for i in range(niveles - 1, 1, -1):
            setattr(self, f"rebnconv{i}d", REBNCONV(medio * 2, medio))
        self.rebnconv1d = REBNCONV(medio * 2, salida)
        self.pool = nn.MaxPool2d(2, stride=2, ceil_mode=True)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        hxin = self.rebnconvin(x)
        encoder = [self.rebnconv1(hxin)]
        for i in range(2, self.niveles):
            encoder.append(getattr(self, f"rebnconv{i}")(self.pool(encoder[-1])))
        hx = getattr(self, f"rebnconv{self.niveles}")(encoder[-1])
        for i in range(self.niveles - 1, 0, -1):
            hx = getattr(self, f"rebnconv{i}d")(torch.cat((hx, encoder[i - 1]), 1))
            if i > 1:
                hx = _como(hx, encoder[i - 2])
        return hx + hxin


class RSU4F(nn.Module):
    """RSU-4F: sin pooling, la escala la cambian las dilataciones 1, 2, 4, 8."""

    def __init__(self, entrada: int, medio: int, salida: int) -> None:
        super().__init__()
        self.rebnconvin = REBNCONV(entrada, salida)
        self.rebnconv1 = REBNCONV(salida, medio, 1)
        self.rebnconv2 = REBNCONV(medio, medio, 2)
        self.rebnconv3 = REBNCONV(medio, medio, 4)
        self.rebnconv4 = REBNCONV(medio, medio, 8)
        self.rebnconv3d = REBNCONV(medio * 2, medio, 4)
        self.rebnconv2d = REBNCONV(medio * 2, medio, 2)
        self.rebnconv1d = REBNCONV(medio * 2, salida, 1)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        hxin = self.rebnconvin(x)
        hx1 = self.rebnconv1(hxin)
        hx2 = self.rebnconv2(hx1)
        hx3 = self.rebnconv3(hx2)
        hx4 = self.rebnconv4(hx3)
        hx3d = self.rebnconv3d(torch.cat((hx4, hx3), 1))
        hx2d = self.rebnconv2d(torch.cat((hx3d, hx2), 1))
        hx1d = self.rebnconv1d(torch.cat((hx2d, hx1), 1))
        return hx1d + hxin


class U2NETP(nn.Module):
    def __init__(self, entrada: int = 3, salida: int = 1) -> None:
        super().__init__()
        self.stage1 = RSU(7, entrada, 16, 64)
        self.stage2 = RSU(6, 64, 16, 64)
        self.stage3 = RSU(5, 64, 16, 64)
        self.stage4 = RSU(4, 64, 16, 64)
        self.stage5 = RSU4F(64, 16, 64)
        self.stage6 = RSU4F(64, 16, 64)
        self.stage5d = RSU4F(128, 16, 64)
        self.stage4d = RSU(4, 128, 16, 64)
        self.stage3d = RSU(5, 128, 16, 64)
        self.stage2d = RSU(6, 128, 16, 64)
        self.stage1d = RSU(7, 128, 16, 64)
        for i in range(1, 7):
            setattr(self, f"side{i}", nn.Conv2d(64, salida, 3, padding=1))
        self.outconv = nn.Conv2d(6 * salida, salida, 1)
        self.pool = nn.MaxPool2d(2, stride=2, ceil_mode=True)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        """Devuelve solo d0, la mascara fusionada, ya con sigmoide."""
        hx1 = self.stage1(x)
        hx2 = self.stage2(self.pool(hx1))
        hx3 = self.stage3(self.pool(hx2))
        hx4 = self.stage4(self.pool(hx3))
        hx5 = self.stage5(self.pool(hx4))
        hx6 = self.stage6(self.pool(hx5))

        hx5d = self.stage5d(torch.cat((_como(hx6, hx5), hx5), 1))
        hx4d = self.stage4d(torch.cat((_como(hx5d, hx4), hx4), 1))
        hx3d = self.stage3d(torch.cat((_como(hx4d, hx3), hx3), 1))
        hx2d = self.stage2d(torch.cat((_como(hx3d, hx2), hx2), 1))
        hx1d = self.stage1d(torch.cat((_como(hx2d, hx1), hx1), 1))

        d1 = self.side1(hx1d)
        lados = [d1] + [
            _como(getattr(self, f"side{i}")(hx), d1)
            for i, hx in zip(range(2, 7), (hx2d, hx3d, hx4d, hx5d, hx6))
        ]
        return torch.sigmoid(self.outconv(torch.cat(lados, 1)))


class EntradaNHWC(nn.Module):
    """(1, 320, 320, 3) RGB en [0, 255] -> (1, 320, 320, 1) mascara en [0, 1]."""

    def __init__(self, red: nn.Module) -> None:
        super().__init__()
        self.red = red
        self.register_buffer("media", torch.tensor(MEDIA).view(1, 3, 1, 1) * 255.0)
        self.register_buffer("desviacion", torch.tensor(DESVIACION).view(1, 3, 1, 1) * 255.0)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = (x.permute(0, 3, 1, 2) - self.media) / self.desviacion
        return self.red(x).permute(0, 2, 3, 1)


def cargar_oficial(ruta: str) -> U2NETP:
    """Carga `u2netp.pth`. `strict=True`: una capa que no cuadre es un error."""
    estado = torch.load(ruta, map_location="cpu", weights_only=True)
    estado = {k.removeprefix("module."): v for k, v in estado.items()}
    red = U2NETP()
    red.load_state_dict(estado, strict=True)
    return red.eval()
