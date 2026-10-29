"""Pesos y reglas del motor, leidos de Mongo (respuestas D.22-D.28, G.38, G.41).

- Iniciales y reglas: documento `recomendacion` de `configuracion`, que es de
  este servicio. Solo se leen los valores definidos; lo que falta o no es valido
  se queda con el valor del codigo, que hoy coincide con lo sembrado.
- Personales: coleccion propia `pesos_usuario`, un documento por usuario
  (`_id` = sub de Cognito). La escribira el job de ajuste de preferencias.

Si Mongo falla, se recomienda con los valores del codigo y se avisa en el log:
una recomendacion con los pesos iniciales sirve; un 503 por la configuracion, no.
"""

import logging
import math
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass, replace

from app.motor.color import ReglasColor
from app.motor.costos import PESOS_INICIALES, Pesos, ReglasCosto
from app.motor.motor import ReglasMotor
from app.motor.mood import ReglasMood

log = logging.getLogger(__name__)

COLECCION_CONFIGURACION = "configuracion"
DOCUMENTO = "recomendacion"
COLECCION_PESOS = "pesos_usuario"
COMPONENTES = ("color", "paleta", "formalidad", "textura")


def abrir_colecciones(mongo_uri: str):
    """Cliente de Mongo y las dos colecciones. Quien las abre cierra el cliente.

    Timeout corto: el Core espera como mucho 10 s, y sin Mongo el motor sigue
    con los valores del codigo.
    """
    from pymongo import MongoClient

    cliente = MongoClient(mongo_uri, serverSelectionTimeoutMS=2000)
    base = cliente.get_default_database("wearhack")
    return cliente, base[COLECCION_CONFIGURACION], base[COLECCION_PESOS]


@dataclass(frozen=True)
class ConfiguracionMotor:
    pesos_iniciales: Pesos = PESOS_INICIALES
    reglas: ReglasMotor = ReglasMotor()


def _numero(valor) -> float | None:
    """Un numero finito, o None. Los `NO_DEFINIDO` de la siembra son texto."""
    if isinstance(valor, bool) or not isinstance(valor, int | float):
        return None
    return float(valor) if math.isfinite(valor) else None


def _pesos(datos) -> Pesos | None:
    """Pesos validos: los cuatro, entre 0 y 1. Si no, None."""
    if not isinstance(datos, dict):
        return None
    valores = {c: _numero(datos.get(c)) for c in COMPONENTES}
    if any(v is None or not 0 <= v <= 1 for v in valores.values()):
        return None
    return Pesos(**valores)


def _entero(valor, minimo: int) -> int | None:
    n = _numero(valor)
    return int(n) if n is not None and n == int(n) and n >= minimo else None


def configuracion_desde(documento: dict | None) -> ConfiguracionMotor:
    """Traduce el documento `recomendacion` a pesos y reglas del motor."""
    defecto = ConfiguracionMotor()
    if not documento:
        return defecto

    pesos = _pesos(documento.get("pesos_iniciales"))
    if pesos is None and "pesos_iniciales" in documento:
        log.warning("pesos_iniciales invalidos en configuracion; se usan los del codigo")

    color = ReglasColor()
    matiz = documento.get("matiz") or {}
    neutros = documento.get("neutros") or {}
    oscuro = neutros.get("oscuro") or {}
    cambios_color = {
        "analoga_max": _numero(matiz.get("analoga_delta_max")),
        "triadica_centro": _numero((matiz.get("triadica") or {}).get("centro")),
        "triadica_semiancho": _numero((matiz.get("triadica") or {}).get("tol")),
        "complementaria_centro": _numero((matiz.get("complementaria") or {}).get("centro")),
        "complementaria_semiancho": _numero((matiz.get("complementaria") or {}).get("tol")),
        "neutro_croma_max": _numero(neutros.get("croma_max")),
        "neutro_oscuro_l_max": _numero(oscuro.get("l_max")),
        "neutro_oscuro_croma_max": _numero(oscuro.get("croma_max")),
    }
    color = replace(color, **{k: v for k, v in cambios_color.items() if v is not None})

    w_mood = _numero(documento.get("w_mood"))
    mood = ReglasMood(color=color, **({"w_mood": w_mood} if w_mood is not None else {}))

    reglas = defecto.reglas
    cambios_motor = {
        "n_outfits": _entero(documento.get("n_outfits"), 1),
        "n_anclas": _entero(documento.get("n_candidatas"), 1),
        "diferencia_minima": _entero(documento.get("min_prendas_diferentes_entre_outfits"), 0),
    }
    reglas = replace(
        reglas,
        costo=ReglasCosto(color=color, paleta=reglas.costo.paleta, mood=mood),
        **{k: v for k, v in cambios_motor.items() if v is not None},
    )
    return ConfiguracionMotor(pesos_iniciales=pesos or defecto.pesos_iniciales, reglas=reglas)


class RepositorioPesosMongo:
    """Cumple `RepositorioPesos` del motor y ademas da las reglas.

    La configuracion se cachea y se relee cada `intervalo` segundos; los pesos
    personales se leen por peticion, que es una consulta por clave primaria.
    """

    def __init__(
        self,
        configuracion,
        pesos,
        intervalo: float,
        reloj: Callable[[], float] = time.monotonic,
    ) -> None:
        self._configuracion = configuracion
        self._pesos = pesos
        self._intervalo = intervalo
        self._reloj = reloj
        self._actual = ConfiguracionMotor()
        self._ultima_consulta: float | None = None
        self._cerrojo = threading.Lock()

    def configuracion(self) -> ConfiguracionMotor:
        with self._cerrojo:
            ahora = self._reloj()
            if self._ultima_consulta is None or ahora - self._ultima_consulta >= self._intervalo:
                self._ultima_consulta = ahora
                try:
                    documento = self._configuracion.find_one({"_id": DOCUMENTO})
                except Exception:
                    log.warning(
                        "No se pudo leer la configuracion; se sigue con la anterior", exc_info=True
                    )
                else:
                    self._actual = configuracion_desde(documento)
            return self._actual

    def pesos_iniciales(self) -> Pesos:
        return self.configuracion().pesos_iniciales

    def pesos_usuario(self, usuario_id: str) -> Pesos | None:
        try:
            documento = self._pesos.find_one({"_id": usuario_id})
        except Exception:
            log.warning("No se pudieron leer los pesos de un usuario", exc_info=True)
            return None
        if documento is None:
            return None
        pesos = _pesos(documento)
        if pesos is None:
            log.warning("Pesos personales invalidos; se usan los iniciales")
        return pesos
