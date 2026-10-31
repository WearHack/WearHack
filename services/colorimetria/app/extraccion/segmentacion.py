"""Regiones de piel, cabello y ojos de un rostro, con MediaPipe.

Dos modelos oficiales de Google (Apache 2.0), que se cargan desde fuera del
repositorio:

- `face_landmarker.task`: 478 landmarks, incluido el iris. Da el recuadro del
  rostro y las zonas a excluir de la piel (ojos, cejas, labios).
- `selfie_multiclass_256x256.tflite`: clases por pixel; se usan cabello (1) y
  piel del rostro (3).

En el producto, el telefono ya manda el rostro recortado (ADR 0016). Aqui se
repite ese recorte para que las imagenes de calibracion lleguen al muestreo
encuadradas igual que llegara un recorte real.

MediaPipe se importa dentro de las funciones: el resto del paquete se usa y se
prueba sin el.
"""

from dataclasses import dataclass
from pathlib import Path

import numpy as np

_CABELLO = 1
_PIEL_ROSTRO = 3


@dataclass(frozen=True)
class ParametrosSegmentacion:
    """Valores provisionales (respuestas A.8: no definidos). Van a `configuracion`."""

    # Lado del recuadro del rostro respecto al lado mayor de los landmarks.
    factor_recorte: float = 2.0
    # Desplazamiento del centro hacia arriba, en alturas del rostro, para que
    # entre el cabello.
    subir_centro: float = 0.15
    # El recorte se reduce a este lado como maximo antes de segmentar.
    lado_maximo: int = 768
    # Margen entre el borde de una region y los landmarks, en fraccion del
    # ancho del rostro.
    margen_piel: float = 0.02
    margen_cabello: float = 0.01
    # La piel se toma solo por encima de los labios: el segmentador cuenta la
    # barba como piel, y la frente, las mejillas y la nariz bastan.
    piel_sobre_labios: bool = True
    # Fraccion del radio del iris que se descarta por la pupila.
    radio_pupila: float = 0.45
    # Radio del iris, en radios, que se quita del ojo para quedarse con la
    # esclerotica: un poco mas que el iris, para no tomar su borde.
    margen_iris_esclerotica: float = 1.15


@dataclass(frozen=True)
class Regiones:
    rgb: np.ndarray  # recorte del rostro (alto, ancho, 3) uint8
    piel: np.ndarray  # mascaras booleanas (alto, ancho)
    cabello: np.ndarray
    ojos: np.ndarray
    ancho_rostro: float  # en pixeles del recorte
    # El blanco del ojo: el contorno del ojo sin el iris. No entra en el
    # clasificador; lo usa el analisis de normalizacion (tecnica T1) como
    # referencia de la luz.
    esclerotica: np.ndarray | None = None


class SinRostro(Exception):
    """No se detecto ningun rostro. En el producto, el telefono pide repetir."""


def _indices(conexiones) -> list[int]:
    return sorted({c.start for c in conexiones} | {c.end for c in conexiones})


class SegmentadorRostro:
    """Envuelve los dos modelos. Usar con `with` para liberar los interpretes."""

    def __init__(
        self,
        ruta_landmarker: Path,
        ruta_segmentador: Path,
        parametros: ParametrosSegmentacion | None = None,
    ) -> None:
        from mediapipe.tasks.python import BaseOptions, vision

        self.parametros = parametros or ParametrosSegmentacion()
        self._landmarker = vision.FaceLandmarker.create_from_options(
            vision.FaceLandmarkerOptions(
                base_options=BaseOptions(model_asset_path=str(ruta_landmarker)),
                num_faces=1,
            )
        )
        self._segmentador = vision.ImageSegmenter.create_from_options(
            vision.ImageSegmenterOptions(
                base_options=BaseOptions(model_asset_path=str(ruta_segmentador)),
                output_category_mask=True,
                output_confidence_masks=False,
            )
        )
        c = vision.FaceLandmarksConnections
        self._excluir_de_piel = [
            _indices(c.FACE_LANDMARKS_LEFT_EYE),
            _indices(c.FACE_LANDMARKS_RIGHT_EYE),
            _indices(c.FACE_LANDMARKS_LEFT_EYEBROW),
            _indices(c.FACE_LANDMARKS_RIGHT_EYEBROW),
            _indices(c.FACE_LANDMARKS_LIPS),
        ]
        self._ovalo = _indices(c.FACE_LANDMARKS_FACE_OVAL)
        self._labios = _indices(c.FACE_LANDMARKS_LIPS)
        self._ojos = [
            (_indices(c.FACE_LANDMARKS_LEFT_EYE), _indices(c.FACE_LANDMARKS_LEFT_IRIS)),
            (_indices(c.FACE_LANDMARKS_RIGHT_EYE), _indices(c.FACE_LANDMARKS_RIGHT_IRIS)),
        ]

    def __enter__(self) -> "SegmentadorRostro":
        return self

    def __exit__(self, *_) -> None:
        self._landmarker.close()
        self._segmentador.close()

    def _landmarks(self, rgb: np.ndarray) -> np.ndarray:
        """Landmarks (478, 2) en pixeles de `rgb`."""
        import mediapipe as mp

        imagen = mp.Image(image_format=mp.ImageFormat.SRGB, data=np.ascontiguousarray(rgb))
        resultado = self._landmarker.detect(imagen)
        if not resultado.face_landmarks:
            raise SinRostro()
        alto, ancho = rgb.shape[:2]
        return np.array([(p.x * ancho, p.y * alto) for p in resultado.face_landmarks[0]])

    def _recortar(self, rgb: np.ndarray, puntos: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        """Recuadro del rostro, como lo haria el telefono, y los landmarks en el."""
        import cv2

        p = self.parametros
        (x0, y0), (x1, y1) = puntos.min(axis=0), puntos.max(axis=0)
        lado = p.factor_recorte * max(x1 - x0, y1 - y0)
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2 - p.subir_centro * (y1 - y0)
        alto, ancho = rgb.shape[:2]
        izq, arr = int(max(0, cx - lado / 2)), int(max(0, cy - lado / 2))
        der, aba = int(min(ancho, cx + lado / 2)), int(min(alto, cy + lado / 2))
        recorte = rgb[arr:aba, izq:der]
        puntos = puntos - (izq, arr)
        escala = p.lado_maximo / max(recorte.shape[:2])
        if escala < 1:
            tam = (round(recorte.shape[1] * escala), round(recorte.shape[0] * escala))
            recorte = cv2.resize(recorte, tam, interpolation=cv2.INTER_AREA)
            puntos = puntos * escala
        return np.ascontiguousarray(recorte), puntos

    def regiones(self, rgb: np.ndarray) -> Regiones:
        import cv2
        import mediapipe as mp

        p = self.parametros
        # Las fotos grandes se detectan reducidas; los landmarks vuelven a escala.
        escala = min(1.0, 1024 / max(rgb.shape[:2]))
        reducida = (
            cv2.resize(rgb, None, fx=escala, fy=escala, interpolation=cv2.INTER_AREA)
            if escala < 1
            else rgb
        )
        recorte, puntos = self._recortar(rgb, self._landmarks(reducida) / escala)

        categorias = self._segmentador.segment(
            mp.Image(image_format=mp.ImageFormat.SRGB, data=recorte)
        ).category_mask.numpy_view()
        categorias = categorias.reshape(recorte.shape[:2])

        ancho_rostro = float(np.ptp(puntos[:, 0]))
        forma = recorte.shape[:2]

        def poligono(indices: list[int]) -> np.ndarray:
            m = np.zeros(forma, np.uint8)
            casco = cv2.convexHull(puntos[indices].astype(np.int32))
            cv2.fillConvexPoly(m, casco, 1)
            return m

        def erosionar(m: np.ndarray, margen: float) -> np.ndarray:
            r = max(1, round(margen * ancho_rostro))
            nucleo = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * r + 1, 2 * r + 1))
            return cv2.erode(m.astype(np.uint8), nucleo)

        piel = (categorias == _PIEL_ROSTRO).astype(np.uint8) & poligono(self._ovalo)
        for indices in self._excluir_de_piel:
            excluir = 1 - erosionar(1 - poligono(indices), p.margen_piel)  # dilatar
            piel &= 1 - excluir
        if p.piel_sobre_labios:
            piel[int(puntos[self._labios, 1].min()) :] = 0
        piel = erosionar(piel, p.margen_piel)

        cabello = erosionar(categorias == _CABELLO, p.margen_cabello)

        ojos = np.zeros(forma, np.uint8)
        esclerotica = np.zeros(forma, np.uint8)
        yy, xx = np.mgrid[: forma[0], : forma[1]]
        for contorno, iris in self._ojos:
            centro = puntos[iris].mean(axis=0)
            radio = float(np.linalg.norm(puntos[iris] - centro, axis=1).mean())
            d2 = (xx - centro[0]) ** 2 + (yy - centro[1]) ** 2
            anillo = (d2 <= radio**2) & (d2 >= (p.radio_pupila * radio) ** 2)
            ojo = poligono(contorno)
            ojos |= anillo.astype(np.uint8) & ojo
            fuera_del_iris = d2 > (p.margen_iris_esclerotica * radio) ** 2
            esclerotica |= ojo & fuera_del_iris.astype(np.uint8)
        # Lejos del parpado y de las pestanas, que oscurecen el borde.
        esclerotica = erosionar(esclerotica, p.margen_piel)

        return Regiones(
            rgb=recorte,
            piel=piel.astype(bool),
            cabello=cabello.astype(bool),
            ojos=ojos.astype(bool),
            ancho_rostro=ancho_rostro,
            esclerotica=esclerotica.astype(bool),
        )
