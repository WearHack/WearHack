"""Centroides de estacion: donde viven, como se publican y como se recargan.

Viven en la coleccion propia `centroides_colorimetria` de Mongo, un documento
por version, para poder revertir (respuestas B.11). Solo una es la vigente. El
servicio la carga al arrancar y la recarga cuando cambia (G.38), sin leer Mongo
en cada peticion: como mucho una consulta ligera cada `intervalo` segundos.

El artefacto se guarda como texto JSON, tal como sale de `calibracion/`. Lleva
nombres de archivo con punto en las claves, y asi ademas queda byte a byte.

El artefacto actual sale de Deep Armocromia: solo para el MVP academico. No va
en la imagen ni en el repositorio; se publica con

    python -m app.jobs.publicar_centroides publicar <artefacto.json>
"""

import json
import logging
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime

from app.clasificador import ClasificadorJerarquico
from app.extraccion.muestreo import Variante
from app.extraccion.segmentacion import ParametrosSegmentacion
from app.extraccion.variables import REGIONES

log = logging.getLogger(__name__)

COLECCION = "centroides_colorimetria"


def abrir_coleccion(mongo_uri: str):
    """Cliente de Mongo y la coleccion de centroides. Quien la abre la cierra.

    Timeout corto: el Core espera como mucho 10 s, y con Mongo caido el
    servicio sigue con los centroides que ya tenia.
    """
    from pymongo import MongoClient

    cliente = MongoClient(mongo_uri, serverSelectionTimeoutMS=2000)
    return cliente, cliente.get_default_database("wearhack")[COLECCION]


class ArtefactoInvalido(ValueError):
    """El JSON no tiene lo que el servicio necesita para clasificar igual que la calibracion."""


@dataclass(frozen=True)
class Artefacto:
    """Todo lo que hace falta para clasificar exactamente como en la calibracion."""

    version: str
    clasificador: ClasificadorJerarquico
    variantes: dict[str, Variante]  # por region
    minimos: dict[str, int]  # pixeles minimos por region, tras el recorte
    segmentacion: ParametrosSegmentacion
    modelos: dict[str, str]  # archivo de MediaPipe -> SHA-256
    experimental: str | None

    @classmethod
    def desde_dict(cls, datos: dict) -> "Artefacto":
        try:
            muestreo = datos["muestreo"]
            segmentacion = dict(datos["segmentacion"])
            modelos = segmentacion.pop("modelos")
            principal = Variante.desde_nombre(muestreo["piel_y_cabello"])
            artefacto = cls(
                version=datos["version"],
                clasificador=ClasificadorJerarquico.desde_dict(datos),
                variantes={
                    "piel": principal,
                    "cabello": principal,
                    "ojos": Variante.desde_nombre(muestreo["ojos"]),
                },
                minimos={r: int(muestreo["pixeles_minimos"][r]) for r in REGIONES},
                segmentacion=ParametrosSegmentacion(**segmentacion),
                modelos=dict(modelos),
                experimental=datos.get("experimental"),
            )
        except (KeyError, TypeError, ValueError) as e:
            raise ArtefactoInvalido(f"Artefacto de centroides invalido: {e!r}") from e
        if not artefacto.modelos:
            raise ArtefactoInvalido("El artefacto no dice con que modelos de MediaPipe se calibro")
        return artefacto


class RepositorioCentroides:
    """Acceso a la coleccion. Recibe una coleccion de pymongo, o algo que se le parezca."""

    def __init__(self, coleccion) -> None:
        self._coleccion = coleccion

    def version_vigente(self) -> str | None:
        documento = self._coleccion.find_one({"vigente": True}, {"_id": 1})
        return documento["_id"] if documento else None

    def cargar(self, version: str) -> dict | None:
        documento = self._coleccion.find_one({"_id": version})
        return json.loads(documento["artefacto"]) if documento else None

    def versiones(self) -> list[dict]:
        return list(
            self._coleccion.find({}, {"_id": 1, "vigente": 1, "publicado_en": 1}).sort(
                "publicado_en", 1
            )
        )

    def publicar(self, datos: dict) -> str:
        """Guarda una version nueva, sin activarla. Una version publicada no se reescribe."""
        version = Artefacto.desde_dict(datos).version
        if self._coleccion.find_one({"_id": version}, {"_id": 1}):
            raise ValueError(f"La version {version} ya existe; una version no se reescribe")
        self._coleccion.insert_one(
            {
                "_id": version,
                "artefacto": json.dumps(datos, ensure_ascii=False),
                "vigente": False,
                "publicado_en": datetime.now(UTC),
            }
        )
        return version

    def activar(self, version: str) -> None:
        """Hace vigente una version publicada. Sirve tambien para revertir.

        Primero se desactiva la anterior y luego se activa la nueva: en el
        instante intermedio no hay vigente, y el servicio sigue con la que tenia
        cargada. Al reves habria dos vigentes a la vez.
        """
        if not self._coleccion.find_one({"_id": version}, {"_id": 1}):
            raise ValueError(f"La version {version} no esta publicada")
        self._coleccion.update_many(
            {"vigente": True, "_id": {"$ne": version}}, {"$set": {"vigente": False}}
        )
        self._coleccion.update_one({"_id": version}, {"$set": {"vigente": True}})


class CentroidesVigentes:
    """La version vigente en memoria, recargada cuando cambia en Mongo.

    Si Mongo falla o la version nueva no es valida, sigue con la que tenia: un
    fallo al recargar no debe tumbar un servicio que ya estaba clasificando.
    """

    def __init__(
        self,
        repositorio: RepositorioCentroides,
        intervalo: float,
        reloj: Callable[[], float] = time.monotonic,
    ) -> None:
        self._repositorio = repositorio
        self._intervalo = intervalo
        self._reloj = reloj
        self._artefacto: Artefacto | None = None
        self._ultima_consulta: float | None = None
        self._cerrojo = threading.Lock()

    def actual(self) -> Artefacto | None:
        with self._cerrojo:
            ahora = self._reloj()
            if self._ultima_consulta is None or ahora - self._ultima_consulta >= self._intervalo:
                self._ultima_consulta = ahora
                self._recargar()
            return self._artefacto

    def _recargar(self) -> None:
        try:
            version = self._repositorio.version_vigente()
        except Exception:
            log.warning("No se pudo consultar la version vigente de los centroides", exc_info=True)
            return
        if version is None or (self._artefacto and self._artefacto.version == version):
            return
        try:
            datos = self._repositorio.cargar(version)
            if datos is None:
                raise ArtefactoInvalido(f"La version {version} desaparecio al cargarla")
            self._artefacto = Artefacto.desde_dict(datos)
        except Exception:
            log.exception("No se pudo cargar la version %s; se mantiene la anterior", version)
            return
        log.info("Centroides %s cargados", version)
