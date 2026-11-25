"""Integra los pesos por offset en un TFLite para el runtime móvil.

Usa el entorno de TensorFlow de las herramientas de exportación. Escribe una
copia nueva y conserva el archivo que entregó el equipo de entrenamiento.
"""

import argparse
from pathlib import Path

import flatbuffers
from flatbuffers.number_types import Uint64Flags
import numpy as np
from tensorflow.lite.python import schema_py_generated as schema


def integrar_pesos(contenido: bytes) -> bytes:
    if contenido[4:8] != b"TFL3":
        raise ValueError("El archivo no es un modelo TFLite")
    raiz = schema.Model.GetRootAsModel(contenido, 0)
    modelo = schema.ModelT.InitFromObj(raiz)
    modificado = False
    for indice, buffer in enumerate(modelo.buffers):
        original = raiz.Buffers(indice)
        # Campos offset y size de Buffer, también con el esquema de TF 2.11.
        offset = original._tab.GetSlot(6, 0, Uint64Flags)
        size = original._tab.GetSlot(8, 0, Uint64Flags)
        if offset <= 1:
            continue
        if original.DataLength() or size == 0 or offset + size > len(contenido):
            raise ValueError(f"Buffer {indice} con un rango de pesos inválido")
        buffer.data = np.frombuffer(contenido, np.uint8, count=size, offset=offset)
        if hasattr(buffer, "offset"):
            buffer.offset = 0
            buffer.size = 0
        modificado = True
    if not modificado:
        return contenido
    constructor = flatbuffers.Builder(len(contenido))
    constructor.Finish(modelo.Pack(constructor), file_identifier=b"TFL3")
    return bytes(constructor.Output())


def main() -> None:
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("original", type=Path)
    cli.add_argument("copia", type=Path)
    args = cli.parse_args()
    if args.original.resolve() == args.copia.resolve():
        cli.error("La copia debe usar una ruta distinta del original")
    resultado = integrar_pesos(args.original.read_bytes())
    with args.copia.open("xb") as archivo:
        archivo.write(resultado)


if __name__ == "__main__":
    main()
