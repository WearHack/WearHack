"""Cuando aplica la estacion del anio.

Las estaciones climaticas solo existen fuera del tropico. En Colombia (y en el
MVP) queda apagada: el clima ya entra por `FRIO`, `TEMPLADO` y `CALIDO`.
"""

LATITUD_MINIMA_ESTACION = 23.5  # grados; el limite del tropico


def estacion_activa(latitud: float | None) -> bool:
    """True solo con |latitud| > 23.5. Sin latitud conocida, apagada."""
    return latitud is not None and abs(latitud) > LATITUD_MINIMA_ESTACION
