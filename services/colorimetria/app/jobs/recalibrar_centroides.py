"""Recalibracion nocturna de los centroides de color. Stub.

Los centroides de cada temporada se corrigen con las correcciones que los
usuarios hacen sobre su clasificacion. Sin esto, un sesgo en el modelo inicial
se queda fijo para siempre.

    python -m app.jobs.recalibrar_centroides
"""

import logging

from app.jobs._runner import salir

log = logging.getLogger(__name__)


def recalibrar() -> None:
    # TODO(ia): leer correcciones_clasificacion, recalcular los centroides por
    # temporada en espacio Lab y guardar la nueva version en configuracion.
    log.warning("Stub: la recalibracion de centroides no hace nada todavia.")


if __name__ == "__main__":
    salir("recalibrar_centroides", recalibrar)
