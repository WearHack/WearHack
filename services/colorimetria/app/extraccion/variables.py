"""Variables del clasificador a partir del color de cada region (respuestas A.5).

Una region que falta deja sus variables en NaN, sin imputar: el clasificador
proyecta la distancia sobre los ejes disponibles. Los ojos son senal secundaria
y el contraste cae a piel-ojos solo si no hay cabello (A.3).
"""

import math

from app.extraccion.muestreo import Muestra

REGIONES = ("piel", "cabello", "ojos")

# Por debajo, a/L y b/L se disparan con el ruido de un pixel casi negro.
_L_MINIMA_PARA_RAZONES = 5.0


def _por_region(r: str, m: Muestra | None) -> dict[str, float]:
    if m is None:
        return dict.fromkeys(
            (f"{r}_{v}" for v in ("L", "a", "b", "C", "S", "V", "calidez", "a_L", "b_L")),
            math.nan,
        )
    razones = m.L >= _L_MINIMA_PARA_RAZONES
    return {
        f"{r}_L": m.L,
        f"{r}_a": m.a,
        f"{r}_b": m.b,
        f"{r}_C": m.croma,
        f"{r}_S": m.S,
        f"{r}_V": m.V,
        f"{r}_calidez": m.b - m.a,
        f"{r}_a_L": m.a / m.L if razones else math.nan,
        f"{r}_b_L": m.b / m.L if razones else math.nan,
    }


def calcular_variables(muestras: dict[str, Muestra | None]) -> dict[str, float]:
    """Todas las variables candidatas. Cuales usa cada capa lo decide la calibracion."""
    piel, cabello, ojos = (muestras.get(r) for r in REGIONES)
    variables: dict[str, float] = {}
    for r in REGIONES:
        variables.update(_por_region(r, muestras.get(r)))

    # El matiz solo de la piel: en cabellos casi negros el angulo es ruido.
    variables["piel_h"] = piel.matiz if piel else math.nan

    def dif(x: Muestra | None, y: Muestra | None) -> float:
        return x.L - y.L if x and y else math.nan

    variables["dL_piel_cabello"] = dif(piel, cabello)
    variables["dL_piel_ojos"] = dif(piel, ojos)
    variables["dL_cabello_ojos"] = dif(cabello, ojos)

    presentes = [m.L for m in (piel, cabello, ojos) if m]
    variables["rango_L"] = max(presentes) - min(presentes) if len(presentes) >= 2 else math.nan

    if piel and cabello:
        variables["contraste"] = abs(piel.L - cabello.L)
    elif piel and ojos:
        variables["contraste"] = abs(piel.L - ojos.L)
    else:
        variables["contraste"] = math.nan

    variables["razon_croma_cabello_piel"] = (
        cabello.croma / piel.croma if piel and cabello and piel.croma > 0 else math.nan
    )
    return variables
