"""Ranking nocturno de prendas puente por usuario. Stub.

Una prenda puente es una del catalogo de marcas aliadas que desbloquea varios
outfits nuevos combinada con lo que el usuario ya tiene. Es lo que monetiza el
producto, y se precalcula de noche porque recorrer el catalogo entero contra
cada closet es caro para hacerlo en linea.

    python -m app.jobs.ranking_prendas_puente
"""

import logging

from app.jobs._runner import salir

log = logging.getLogger(__name__)


def rankear() -> None:
    # TODO(ia): por cada usuario, cruzar su closet con el catalogo y ordenar
    # las prendas candidatas por cuantos outfits validos nuevos habilitan.
    log.warning("Stub: el ranking de prendas puente no hace nada todavia.")


if __name__ == "__main__":
    salir("ranking_prendas_puente", rankear)
