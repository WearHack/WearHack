"""Ajuste nocturno del vector de pesos de cada usuario. Stub.

Lo que el usuario elige ponerse dice mas que lo que declara. Este job mueve su
vector de pesos segun las selecciones nuevas.

Solo se ajusta a partir de 10 selecciones nuevas. Por debajo de ese umbral el
ruido pesa mas que la senal y el vector oscilaria de un dia para otro.

    python -m app.jobs.ajuste_preferencias
"""

import logging

from app.jobs._runner import salir

log = logging.getLogger(__name__)

UMBRAL_SELECCIONES_NUEVAS = 10


def ajustar() -> None:
    # TODO(ia): leer las selecciones posteriores al ultimo ajuste, saltar a los
    # usuarios por debajo del umbral y mover el vector de pesos del resto.
    log.warning(
        "Stub: el ajuste de preferencias no hace nada todavia (umbral: %d selecciones).",
        UMBRAL_SELECCIONES_NUEVAS,
    )


if __name__ == "__main__":
    salir("ajuste_preferencias", ajustar)
