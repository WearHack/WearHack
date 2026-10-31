"""La tarjeta de referencia: medir sus parches y comprobar que sirve.

Las cajas se marcan a mano (`marcar_tarjeta`) en pixeles de la foto completa ya
orientada, y se guardan en un JSON local, fuera del repositorio:

    {"P3_LEDC_D2_R1_G": {"blanco": [x0, y0, x1, y1], "gris": [...], "negro": [...]}}

La tarjeta del equipo es un juego generico (blanco, gris 18 %, negro) sin
especificacion de neutralidad. `validar` comprueba que el blanco y el gris
"ven" la misma luz: si los dos son neutros, la luz que estima uno y la que
estima el otro coinciden. Si no, alguno tiene tinte y REF no es confiable.
"""

import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from app.extraccion.color import srgb_a_lineal

PARCHES = ("blanco", "gris", "negro")
# Fraccion de cada lado que se descarta: los bordes de la caja marcada a mano.
_MARGEN = 0.2
_RECORTADO = 254

# Validacion. Provisionales: el protocolo no los fija; se revisan con la tarjeta real.
ANGULO_ACEPTABLE = 3.0  # grados entre la luz del blanco y la del gris
MAX_RECORTADOS = 0.01  # fraccion de pixeles saturados en un parche
MAX_DISPERSION = 0.08  # desviacion relativa dentro del parche (brillos, sombras)

Caja = tuple[int, int, int, int]


@dataclass(frozen=True)
class Parche:
    lineal: np.ndarray  # mediana RGB lineal, (3,)
    recortados: float  # fraccion de pixeles con algun canal saturado
    dispersion: float  # desviacion de la luminancia / su mediana


def cargar_cajas(ruta: Path | None) -> dict[str, dict[str, Caja]]:
    if ruta is None or not ruta.is_file():
        return {}
    datos = json.loads(ruta.read_text(encoding="utf-8"))
    return {
        toma: {p: tuple(int(v) for v in caja) for p, caja in cajas.items()} for toma, cajas in datos.items()
    }


def guardar_cajas(ruta: Path, cajas: dict[str, dict[str, Caja]]) -> None:
    ruta.parent.mkdir(parents=True, exist_ok=True)
    ruta.write_text(
        json.dumps({t: {p: list(c) for p, c in cs.items()} for t, cs in sorted(cajas.items())}, indent=2),
        encoding="utf-8",
    )


def medir(rgb: np.ndarray, caja: Caja) -> Parche:
    """El parche dentro de la caja, sin sus bordes."""
    # Se acepta la caja marcada en cualquier sentido.
    x0, x1 = sorted((caja[0], caja[2]))
    y0, y1 = sorted((caja[1], caja[3]))
    dx, dy = int((x1 - x0) * _MARGEN), int((y1 - y0) * _MARGEN)
    zona = np.asarray(rgb)[y0 + dy : y1 - dy, x0 + dx : x1 - dx].reshape(-1, 3)
    if len(zona) == 0:
        raise ValueError(f"La caja {caja} no tiene pixeles")
    recortados = float((zona >= _RECORTADO).any(axis=1).mean())
    lineal = srgb_a_lineal(zona)
    luz = lineal.sum(axis=1)
    mediana = float(np.median(luz))
    dispersion = float(np.std(luz) / mediana) if mediana > 0 else float("inf")
    return Parche(lineal=np.median(lineal, axis=0), recortados=recortados, dispersion=dispersion)


@dataclass(frozen=True)
class Validacion:
    angulo_blanco_gris: float
    problemas: list[str]

    @property
    def sirve(self) -> bool:
        return not self.problemas


def validar(parches: dict[str, Parche]) -> Validacion:
    """Si una foto de la tarjeta permite usarla como referencia."""
    from normalizacion.tecnicas import angulo

    problemas = []
    for nombre, p in parches.items():
        if p.recortados > MAX_RECORTADOS:
            problemas.append(f"{nombre}: {p.recortados:.0%} saturado (sobreexpuesta)")
        if p.dispersion > MAX_DISPERSION:
            problemas.append(f"{nombre}: poco uniforme ({p.dispersion:.0%}); brillo o sombra encima")
    blanco, gris, negro = (parches.get(n) for n in PARCHES)
    ang = angulo(blanco.lineal, gris.lineal) if blanco and gris else float("nan")
    if ang > ANGULO_ACEPTABLE:
        problemas.append(f"el blanco y el gris ven luces distintas ({ang:.1f} grados): alguno no es neutro")
    if blanco and gris and negro:
        luz = [p.lineal.sum() for p in (negro, gris, blanco)]
        if not luz[0] < luz[1] < luz[2]:
            problemas.append("los parches no van de oscuro a claro: revisa las cajas")
    return Validacion(angulo_blanco_gris=ang, problemas=problemas)
