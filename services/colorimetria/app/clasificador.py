"""Clasificador jerarquico por centroide mas cercano (respuestas A.2, A.5, A.6).

Capa 1, subtono (calido o frio); capa 2, contraste (alto o bajo). Las dos dan
la estacion. Cada capa usa su propio subconjunto de variables, estandarizadas
con la media y la desviacion del conjunto de entrenamiento.

- Distancia euclidiana proyectada sobre los ejes disponibles: una variable en
  NaN no se imputa, se salta.
- Decision dura; la confianza es el inverso de la distancia, normalizado.
- La probabilidad de una estacion es el producto de las de sus dos capas, y de
  ahi sale la segunda opcion.

Los centroides se calculan en `calibracion/` y llegan aqui como JSON.
"""

import json
import math
from dataclasses import dataclass
from pathlib import Path

import numpy as np

# Estacion -> (subtono, contraste).
ESTACIONES = {
    "PRIMAVERA": ("CALIDO", "BAJO"),
    "VERANO": ("FRIO", "BAJO"),
    "OTONO": ("CALIDO", "ALTO"),
    "INVIERNO": ("FRIO", "ALTO"),
}
CAPAS = ("subtono", "contraste")


def distancias(x: np.ndarray, centroides: np.ndarray) -> np.ndarray:
    """(n, d) contra (k, d) -> (n, k). Fila en NaN si no queda ningun eje."""
    diferencias = x[:, None, :] - centroides[None, :, :]
    disponibles = ~np.isnan(diferencias)
    d = np.sqrt(np.nansum(diferencias**2, axis=2))
    return np.where(disponibles.any(axis=2), d, np.nan)


def probabilidades(d: np.ndarray, epsilon: float = 1e-9) -> np.ndarray:
    """Inverso de la distancia, normalizado por fila."""
    inversa = 1.0 / (d + epsilon)
    return inversa / inversa.sum(axis=1, keepdims=True)


@dataclass(frozen=True)
class Capa:
    variables: list[str]
    clases: list[str]
    centroides: np.ndarray  # (clases, variables), ya estandarizados


@dataclass(frozen=True)
class Resultado:
    estacion: str
    segunda_opcion: str
    probabilidades: dict[str, float]  # por estacion
    capas: dict[str, dict[str, float]]  # por capa y clase
    ejes_usados: list[str]  # se guardan con la clasificacion (B.12)


class ClasificadorJerarquico:
    def __init__(
        self,
        capas: dict[str, Capa],
        media: dict[str, float],
        desviacion: dict[str, float],
        version: str,
    ) -> None:
        self.capas = capas
        self.media = media
        self.desviacion = desviacion
        self.version = version

    @property
    def variables(self) -> list[str]:
        return sorted({v for c in self.capas.values() for v in c.variables})

    def estandarizar(self, x: np.ndarray, variables: list[str]) -> np.ndarray:
        media = np.array([self.media[v] for v in variables])
        desviacion = np.array([self.desviacion[v] for v in variables])
        return (x - media) / desviacion

    def probabilidades_por_capa(self, x: np.ndarray, variables: list[str]) -> dict[str, np.ndarray]:
        """`x` (n, len(variables)) sin estandarizar -> por capa, (n, clases)."""
        indice = {v: i for i, v in enumerate(variables)}
        salida = {}
        for nombre, capa in self.capas.items():
            columnas = x[:, [indice[v] for v in capa.variables]]
            z = self.estandarizar(columnas, capa.variables)
            salida[nombre] = probabilidades(distancias(z, capa.centroides))
        return salida

    def probabilidades_por_estacion(
        self, por_capa: dict[str, np.ndarray]
    ) -> tuple[list[str], np.ndarray]:
        estaciones = list(ESTACIONES)
        columnas = []
        for e in estaciones:
            p = np.ones(len(next(iter(por_capa.values()))))
            for nombre, clase in zip(CAPAS, ESTACIONES[e], strict=True):
                p = p * por_capa[nombre][:, self.capas[nombre].clases.index(clase)]
            columnas.append(p)
        return estaciones, np.stack(columnas, axis=1)

    def clasificar(self, variables: dict[str, float]) -> Resultado | None:
        """None si alguna capa no tiene ningun eje disponible."""
        nombres = self.variables
        x = np.array([[variables.get(v, math.nan) for v in nombres]], dtype=float)
        por_capa = self.probabilidades_por_capa(x, nombres)
        if any(np.isnan(p).any() for p in por_capa.values()):
            return None
        estaciones, p = self.probabilidades_por_estacion(por_capa)
        orden = np.argsort(-p[0])
        return Resultado(
            estacion=estaciones[orden[0]],
            segunda_opcion=estaciones[orden[1]],
            probabilidades={e: float(p[0, i]) for i, e in enumerate(estaciones)},
            capas={
                nombre: {c: float(por_capa[nombre][0, i]) for i, c in enumerate(capa.clases)}
                for nombre, capa in self.capas.items()
            },
            ejes_usados=[v for v in nombres if not math.isnan(variables.get(v, math.nan))],
        )

    def a_dict(self) -> dict:
        return {
            "version": self.version,
            "estandarizacion": {"media": self.media, "desviacion": self.desviacion},
            "capas": {
                nombre: {
                    "variables": capa.variables,
                    "centroides": {
                        c: capa.centroides[i].tolist() for i, c in enumerate(capa.clases)
                    },
                }
                for nombre, capa in self.capas.items()
            },
        }

    @classmethod
    def desde_dict(cls, datos: dict) -> "ClasificadorJerarquico":
        capas = {
            nombre: Capa(
                variables=c["variables"],
                clases=list(c["centroides"]),
                centroides=np.array(list(c["centroides"].values()), dtype=float),
            )
            for nombre, c in datos["capas"].items()
        }
        e = datos["estandarizacion"]
        return cls(capas, e["media"], e["desviacion"], datos["version"])

    @classmethod
    def desde_archivo(cls, ruta: Path) -> "ClasificadorJerarquico":
        return cls.desde_dict(json.loads(Path(ruta).read_text(encoding="utf-8")))
