"""Del PNG del recorte facial a la estacion de color.

Mismo camino que la calibracion: segmentar con MediaPipe, muestrear cada region
con la variante y el minimo que eligio la calibracion, calcular las variables y
clasificar. Todo eso lo dice el artefacto vigente, asi que el servicio no tiene
parametros propios que se puedan desalinear de los centroides.

El recorte no se guarda en ningun sitio: entra, se analiza y se descarta.
"""

import hashlib
import io
import logging
import threading
from collections.abc import Callable
from pathlib import Path

import numpy as np

from app.centroides import Artefacto, CentroidesVigentes
from app.extraccion.muestreo import Muestra, muestrear_regiones
from app.extraccion.segmentacion import ParametrosSegmentacion, SegmentadorRostro, SinRostro
from app.extraccion.variables import calcular_variables

log = logging.getLogger(__name__)

# Un recorte facial no necesita mas: el segmentador reduce a 768 px de lado.
MAX_PIXELES = 4096 * 4096


class RecorteInvalido(Exception):
    """El recorte no sirve para clasificar. Es del usuario: puede repetir la foto."""


class ServicioNoDisponible(Exception):
    """Falta algo del lado del servicio (centroides, modelos). Reintentable mas tarde."""


def decodificar_png(datos: bytes) -> np.ndarray:
    """PNG -> RGB sRGB uint8 (alto, ancho, 3).

    Si el PNG trae perfil ICC (un iPhone captura en Display P3), se convierte a
    sRGB, que es lo que asume el muestreo (respuestas A.9, nivel 0).
    """
    from PIL import Image, ImageCms, UnidentifiedImageError

    try:
        imagen = Image.open(io.BytesIO(datos))
        if imagen.format != "PNG":
            raise RecorteInvalido(f"El recorte debe ser PNG, no {imagen.format}")
        # Antes de descomprimir: 5 MB de PNG pueden ser cientos de megapixeles.
        if imagen.width * imagen.height > MAX_PIXELES:
            raise RecorteInvalido("El recorte tiene demasiados pixeles")
        imagen.load()
    except (UnidentifiedImageError, Image.DecompressionBombError, OSError) as e:
        raise RecorteInvalido("El recorte no es un PNG legible") from e

    icc = imagen.info.get("icc_profile")
    imagen = imagen.convert("RGB")
    if icc:
        try:
            origen = ImageCms.ImageCmsProfile(io.BytesIO(icc))
            imagen = ImageCms.profileToProfile(imagen, origen, ImageCms.createProfile("sRGB"))
        except (ImageCms.PyCMSError, OSError) as e:
            raise RecorteInvalido("El perfil de color del recorte no se puede interpretar") from e
    return np.asarray(imagen, dtype=np.uint8)


def sha256_de(ruta: Path) -> str:
    h = hashlib.sha256()
    with ruta.open("rb") as f:
        for bloque in iter(lambda: f.read(1 << 20), b""):
            h.update(bloque)
    return h.hexdigest()


class Analizador:
    """Segmenta y clasifica. Un solo segmentador, compartido con un cerrojo:
    los interpretes de MediaPipe no son seguros entre hilos y cargar uno por
    peticion costaria mas que esperar.
    """

    def __init__(
        self,
        ruta_modelos: Path,
        fabrica_segmentador: Callable[..., SegmentadorRostro] = SegmentadorRostro,
    ) -> None:
        self._ruta_modelos = Path(ruta_modelos)
        self._fabrica = fabrica_segmentador
        self._segmentador = None
        self._clave: tuple[ParametrosSegmentacion, tuple] | None = None
        self._hashes: dict[str, str] = {}
        self._cerrojo = threading.Lock()

    def cerrar(self) -> None:
        with self._cerrojo:
            if self._segmentador is not None:
                self._segmentador.__exit__(None, None, None)
                self._segmentador = None

    def analizar(self, rgb: np.ndarray, artefacto: Artefacto) -> dict:
        with self._cerrojo:
            segmentador = self._segmentador_para(artefacto)
            try:
                regiones = segmentador.regiones(rgb)
            except SinRostro as e:
                raise RecorteInvalido("No se detecto un rostro en el recorte") from e

        muestras = muestrear_regiones(
            regiones.rgb,
            {"piel": regiones.piel, "cabello": regiones.cabello, "ojos": regiones.ojos},
            artefacto.variantes,
            artefacto.minimos,
        )
        if muestras["piel"] is None:
            # Sin piel no hay subtono, y el perfil la exige.
            raise RecorteInvalido("No hay piel suficiente en el recorte para medir el color")
        resultado = artefacto.clasificador.clasificar(calcular_variables(muestras))
        if resultado is None:
            raise RecorteInvalido("No hay regiones suficientes para clasificar")

        return {
            "temporada": resultado.estacion,
            "confianza": resultado.probabilidades[resultado.estacion],
            "ejes": resultado.ejes_usados,
            "piel": _lab(muestras["piel"]),
            "cabello": _lab(muestras["cabello"]),
            "iris": _lab(muestras["ojos"]),
            "segunda_opcion": resultado.segunda_opcion,
            "probabilidades": {"estaciones": resultado.probabilidades, **resultado.capas},
            "version_centroides": artefacto.version,
            "experimental": artefacto.experimental,
        }

    def _segmentador_para(self, artefacto: Artefacto) -> SegmentadorRostro:
        """El segmentador con los parametros y modelos de este artefacto.

        Con otros modelos u otros parametros, las regiones no serian las de la
        calibracion y los centroides no valdrian: mejor no responder.
        """
        clave = (artefacto.segmentacion, tuple(sorted(artefacto.modelos.items())))
        if self._segmentador is not None and self._clave == clave:
            return self._segmentador
        for archivo, esperado in artefacto.modelos.items():
            if self._hash(archivo) != esperado:
                raise ServicioNoDisponible(
                    f"El modelo {archivo} falta, no se puede leer o no es el que uso "
                    f"la calibracion de {artefacto.version}"
                )
        if self._segmentador is not None:
            self._segmentador.__exit__(None, None, None)
            self._segmentador = None
        try:
            self._segmentador = self._fabrica(
                self._ruta_modelos / "face_landmarker.task",
                self._ruta_modelos / "selfie_multiclass_256x256.tflite",
                artefacto.segmentacion,
            )
        except Exception as e:
            log.exception("No se pudo cargar MediaPipe")
            raise ServicioNoDisponible("No se pudieron cargar los modelos de MediaPipe") from e
        self._clave = clave
        log.info("Segmentador listo para los centroides %s", artefacto.version)
        return self._segmentador

    def _hash(self, archivo: str) -> str | None:
        if archivo not in self._hashes:
            ruta = self._ruta_modelos / archivo
            try:
                self._hashes[archivo] = sha256_de(ruta)
            except OSError:
                log.exception("No se puede leer el modelo %s", ruta)
                return None
        return self._hashes[archivo]


class ServicioColorimetria:
    """Lo que usa el endpoint: los centroides vigentes y el analizador."""

    def __init__(self, centroides: CentroidesVigentes, analizador: Analizador) -> None:
        self.centroides = centroides
        self.analizador = analizador

    def analizar_png(self, datos: bytes) -> dict:
        artefacto = self.centroides.actual()
        if artefacto is None:
            raise ServicioNoDisponible("No hay centroides vigentes publicados")
        return self.analizador.analizar(decodificar_png(datos), artefacto)


def _lab(m: Muestra | None) -> dict[str, float] | None:
    return {"l": round(m.L, 3), "a": round(m.a, 3), "b": round(m.b, 3)} if m else None
