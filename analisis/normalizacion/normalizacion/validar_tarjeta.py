"""Comprueba que la tarjeta sirve de referencia, antes de la sesion de captura.

    python -m normalizacion.validar_tarjeta --cajas RUTA/tarjetas.json FOTO [FOTO ...]

Toma fotos de la tarjeta sola (blanco, gris y negro juntos) bajo dos o tres
luces distintas, marca sus parches con `marcar_tarjeta` y pasa las mismas fotos
aqui. Para cada foto dice:

- el angulo entre la luz que "ve" el blanco y la que ve el gris. Si los dos son
  neutros, coinciden; si no, alguno tiene tinte;
- si algun parche esta saturado o tiene un brillo o una sombra encima.

Si falla bajo alguna luz, la tarjeta no sirve como referencia (REF). No hace
falta la configuracion completa: solo las fotos y sus cajas.
"""

import argparse
import sys
from pathlib import Path

from normalizacion.imagenes import leer_srgb
from normalizacion.tarjeta import ANGULO_ACEPTABLE, PARCHES, cargar_cajas, medir, validar


def principal(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("fotos", nargs="+", type=Path)
    parser.add_argument("--cajas", type=Path, required=True)
    args = parser.parse_args(argv)

    cajas = cargar_cajas(args.cajas)
    fallos = 0
    for foto in args.fotos:
        if foto.stem not in cajas:
            print(f"{foto.name}: sin cajas; marcala primero con marcar_tarjeta")
            fallos += 1
            continue
        imagen = leer_srgb(foto)
        parches = {p: medir(imagen, c) for p, c in cajas[foto.stem].items() if p in PARCHES}
        resultado = validar(parches)
        estado = "SIRVE" if resultado.sirve else "NO SIRVE"
        print(f"{foto.name}: {estado} (blanco vs gris: {resultado.angulo_blanco_gris:.1f} grados)")
        for problema in resultado.problemas:
            print(f"  - {problema}")
        fallos += not resultado.sirve
    print(
        f"\nCriterio: blanco y gris a menos de {ANGULO_ACEPTABLE:g} grados, sin parches "
        "saturados ni brillos. Es provisional: el protocolo no lo fija."
    )
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(principal())
