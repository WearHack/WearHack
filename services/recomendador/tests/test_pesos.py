"""Pesos y reglas del motor desde Mongo, con colecciones falsas."""

from app.motor.costos import PESOS_INICIALES, Pesos
from app.motor.motor import ReglasMotor
from app.pesos import ConfiguracionMotor, RepositorioPesosMongo, configuracion_desde

# El documento tal como lo siembra infra/datos/wearhack-mongo-setup.js.
SEMBRADO = {
    "_id": "recomendacion",
    "bandas_clima_c": {"frio_menor_que": 14, "calido_mayor_que": 22},
    "pesos_iniciales": {"color": 0.35, "paleta": 0.25, "formalidad": 0.25, "textura": 0.15},
    "w_mood": 0.2,
    "w_estacion": 0.1,
    "n_outfits": 3,
    "n_candidatas": 10,
    "min_prendas_diferentes_entre_outfits": 2,
    "matiz": {
        "analoga_delta_max": 30,
        "triadica": {"centro": 120, "tol": 15},
        "complementaria": {"centro": 180, "tol": 20},
    },
    "neutros": {"croma_max": 15, "oscuro": {"l_max": 35, "croma_max": 30}},
    "curva_croma": "NO_DEFINIDO",
    "corte_calido_frio": "NO_DEFINIDO",
}


class ColeccionFalsa:
    def __init__(self, *documentos: dict) -> None:
        self.documentos = {d["_id"]: d for d in documentos}
        self.falla = False
        self.consultas = 0

    def find_one(self, filtro: dict) -> dict | None:
        self.consultas += 1
        if self.falla:
            raise ConnectionError("Mongo no responde")
        return self.documentos.get(filtro["_id"])


class Reloj:
    def __init__(self) -> None:
        self.ahora = 0.0

    def __call__(self) -> float:
        return self.ahora


def test_lo_sembrado_coincide_con_el_codigo():
    """Si alguien cambia uno de los dos, este test lo dice."""
    assert configuracion_desde(SEMBRADO) == ConfiguracionMotor()


def test_los_valores_definidos_se_respetan():
    documento = {
        **SEMBRADO,
        "pesos_iniciales": {"color": 0.4, "paleta": 0.2, "formalidad": 0.3, "textura": 0.1},
        "n_outfits": 5,
        "w_mood": 0.3,
        "matiz": {**SEMBRADO["matiz"], "analoga_delta_max": 25},
    }
    c = configuracion_desde(documento)

    assert c.pesos_iniciales == Pesos(color=0.4, paleta=0.2, formalidad=0.3, textura=0.1)
    assert c.reglas.n_outfits == 5
    assert c.reglas.costo.mood.w_mood == 0.3
    # La misma regla de color en el costo y en el mood.
    assert c.reglas.costo.color.analoga_max == c.reglas.costo.mood.color.analoga_max == 25


def test_lo_invalido_o_no_definido_se_queda_con_el_codigo():
    documento = {
        **SEMBRADO,
        "pesos_iniciales": {"color": 2.0, "paleta": 0.2, "formalidad": 0.3, "textura": 0.1},
        "n_outfits": "NO_DEFINIDO",
        "n_candidatas": 0,
        "w_mood": True,
    }
    c = configuracion_desde(documento)

    assert c.pesos_iniciales == PESOS_INICIALES
    assert c.reglas.n_outfits == ReglasMotor().n_outfits
    assert c.reglas.n_anclas == ReglasMotor().n_anclas
    assert c.reglas.costo.mood.w_mood == ReglasMotor().costo.mood.w_mood


def test_sin_documento_se_usa_el_codigo():
    assert configuracion_desde(None) == ConfiguracionMotor()


def test_la_configuracion_se_relee_solo_cuando_toca():
    configuracion = ColeccionFalsa(SEMBRADO)
    reloj = Reloj()
    repo = RepositorioPesosMongo(configuracion, ColeccionFalsa(), intervalo=60, reloj=reloj)

    repo.configuracion()
    repo.configuracion()
    assert configuracion.consultas == 1

    configuracion.documentos["recomendacion"] = {**SEMBRADO, "n_outfits": 4}
    reloj.ahora = 60
    assert repo.configuracion().reglas.n_outfits == 4


def test_si_mongo_falla_sigue_con_lo_que_tenia():
    configuracion = ColeccionFalsa({**SEMBRADO, "n_outfits": 4})
    reloj = Reloj()
    repo = RepositorioPesosMongo(configuracion, ColeccionFalsa(), intervalo=1, reloj=reloj)
    assert repo.configuracion().reglas.n_outfits == 4

    configuracion.falla = True
    reloj.ahora = 5
    assert repo.configuracion().reglas.n_outfits == 4


def test_pesos_personales():
    pesos = ColeccionFalsa(
        {"_id": "u-1", "color": 0.5, "paleta": 0.1, "formalidad": 0.3, "textura": 0.1},
        {"_id": "u-roto", "color": 0.5},
    )
    repo = RepositorioPesosMongo(ColeccionFalsa(SEMBRADO), pesos, intervalo=60)

    assert repo.pesos_usuario("u-1") == Pesos(color=0.5, paleta=0.1, formalidad=0.3, textura=0.1)
    assert repo.pesos_usuario("u-nuevo") is None
    assert repo.pesos_usuario("u-roto") is None

    pesos.falla = True
    assert repo.pesos_usuario("u-1") is None
