"""Publica, activa o lista versiones de los centroides de estacion.

    python -m app.jobs.publicar_centroides publicar <artefacto.json> [--activar]
    python -m app.jobs.publicar_centroides activar <version>
    python -m app.jobs.publicar_centroides listar

`publicar` guarda la version sin activarla, salvo con `--activar`. `activar`
hace vigente una version ya publicada, y sirve para revertir. El servicio la
recoge solo, en menos de `INTERVALO_RECARGA_CENTROIDES` segundos.

El artefacto actual sale de Deep Armocromia (solo MVP academico): no va en la
imagen. Se monta solo para este comando, por ejemplo:

    docker compose run --rm -v <carpeta del artefacto>:/artefactos:ro colorimetria \\
        python -m app.jobs.publicar_centroides publicar /artefactos/centroides-4-estaciones-v1.json --activar
"""

import argparse
import json
import logging
from pathlib import Path

from app.centroides import RepositorioCentroides, abrir_coleccion
from app.config import ajustes
from app.jobs._runner import salir

log = logging.getLogger(__name__)


def argumentos(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ordenes = parser.add_subparsers(dest="orden", required=True)
    publicar = ordenes.add_parser("publicar", help="Guarda una version nueva")
    publicar.add_argument("artefacto", type=Path)
    publicar.add_argument("--activar", action="store_true", help="Y la hace vigente")
    activar = ordenes.add_parser("activar", help="Hace vigente una version publicada")
    activar.add_argument("version")
    ordenes.add_parser("listar", help="Versiones publicadas y cual es la vigente")
    return parser.parse_args(argv)


def ejecutar(args: argparse.Namespace, repositorio: RepositorioCentroides) -> None:
    if args.orden == "publicar":
        datos = json.loads(args.artefacto.read_text(encoding="utf-8"))
        version = repositorio.publicar(datos)
        log.info("Centroides %s publicados", version)
        if args.activar:
            repositorio.activar(version)
            log.info("Centroides %s vigentes", version)
    elif args.orden == "activar":
        repositorio.activar(args.version)
        log.info("Centroides %s vigentes", args.version)
    else:
        for v in repositorio.versiones():
            marca = "vigente" if v.get("vigente") else ""
            log.info("%s  %s  %s", v["_id"], v.get("publicado_en"), marca)


def principal(argv: list[str] | None = None) -> None:
    # Los argumentos se leen antes de configurar logs y trazas: un error de uso
    # sale con el mensaje de argparse, no como un job fallido.
    args = argumentos(argv)

    def tarea() -> None:
        cliente, coleccion = abrir_coleccion(ajustes().mongo_uri)
        try:
            ejecutar(args, RepositorioCentroides(coleccion))
        finally:
            cliente.close()

    salir(f"publicar_centroides.{args.orden}", tarea)


if __name__ == "__main__":
    principal()
