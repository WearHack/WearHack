"""Marca a mano los parches de la tarjeta (blanco, gris y negro) en cada foto.

    python -m normalizacion.marcar_tarjeta --cajas RUTA/tarjetas.json FOTO [FOTO ...]
    python -m normalizacion.marcar_tarjeta --sesion

Por foto se abre una ventana: haz clic en dos esquinas opuestas de cada parche,
en este orden: blanco, gris, negro. Basta con quedarse dentro del parche: el
borde de la caja se descarta al medir. Cerrar la ventana sin terminar salta la
foto. Lo marcado se guarda despues de cada foto, asi que se puede parar y
seguir otro dia.

Con `--sesion` marca las tomas `R1` de la boveda que aun no tienen cajas, y las
guarda en la ruta `tarjetas` de la configuracion. Las cajas son pixeles de la
foto **ya orientada** segun el EXIF, que es como la lee el analisis.
"""

import argparse
import sys
from pathlib import Path

from normalizacion import configuracion, lotes
from normalizacion.imagenes import leer_srgb
from normalizacion.tarjeta import PARCHES, cargar_cajas, guardar_cajas


def marcar(ruta_foto: Path) -> dict | None:
    """Las tres cajas de una foto, o None si se cerro la ventana."""
    import matplotlib.pyplot as plt

    imagen = leer_srgb(ruta_foto)
    figura, eje = plt.subplots(figsize=(10, 8))
    eje.imshow(imagen)
    eje.set_axis_off()
    cajas = {}
    for parche in PARCHES:
        eje.set_title(f"{ruta_foto.name}: dos esquinas del parche {parche.upper()}")
        figura.canvas.draw_idle()
        puntos = plt.ginput(2, timeout=0)
        if len(puntos) < 2:
            plt.close(figura)
            return None
        (x0, y0), (x1, y1) = puntos
        cajas[parche] = (round(x0), round(y0), round(x1), round(y1))
        eje.add_patch(
            plt.Rectangle((min(x0, x1), min(y0, y1)), abs(x1 - x0), abs(y1 - y0), fill=False, color="red")
        )
    plt.close(figura)
    return cajas


def principal(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("fotos", nargs="*", type=Path)
    parser.add_argument("--cajas", type=Path, help="JSON donde guardar las cajas (fuera del repo)")
    parser.add_argument("--sesion", action="store_true", help="Las tomas R1 de la boveda")
    args = parser.parse_args(argv)

    if args.sesion:
        rutas = configuracion.cargar()
        if rutas.tarjetas is None:
            parser.error("La configuracion no tiene la clave 'tarjetas'.")
        destino = rutas.tarjetas
        pendientes = {t.id: t.foto for t in lotes.cargar(rutas.lotes).tomas if t.tarjeta}
    else:
        if not args.cajas or not args.fotos:
            parser.error("Indica --cajas y al menos una foto, o usa --sesion.")
        destino = args.cajas
        pendientes = {f.stem: f for f in args.fotos}
    # Se mira desde la carpeta existente mas cercana: la de destino puede no existir aun.
    existente = destino.resolve().parent
    while not existente.exists():
        existente = existente.parent
    if configuracion.esta_en_un_repositorio(existente):
        parser.error(f"{destino} esta dentro de un repositorio: las cajas van fuera.")

    cajas = cargar_cajas(destino)
    for clave, foto in pendientes.items():
        if clave in cajas:
            continue
        marcadas = marcar(foto)
        if marcadas is None:
            print(f"Saltada: {foto.name}")
            continue
        cajas[clave] = marcadas
        guardar_cajas(destino, cajas)
        print(f"Marcada: {foto.name}")
    print(f"{len(cajas)} fotos con cajas en {destino}")
    return 0


if __name__ == "__main__":
    sys.exit(principal())
