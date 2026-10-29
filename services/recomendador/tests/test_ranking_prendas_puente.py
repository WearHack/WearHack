"""Job de ranking de prendas puente (#38), contra colecciones falsas."""

from datetime import UTC, datetime

from app.jobs.ranking_prendas_puente import (
    COLECCION_RANKING,
    eventos_desde,
    prenda_desde_documento,
    prendas_validas,
    rankear_todos,
    reglas_puente_desde,
)
from app.motor.modelos import Clima, Formalidad, Patron, Slot, Textura

AHORA = datetime(2026, 10, 30, 3, 0, tzinfo=UTC)


class ColeccionFalsa:
    def __init__(self, *documentos: dict) -> None:
        self.documentos = {d["_id"]: dict(d) for d in documentos}

    def _cumple(self, documento: dict, filtro: dict) -> bool:
        return all(documento.get(k) == v for k, v in filtro.items())

    def find(self, filtro: dict) -> list[dict]:
        return [d for d in self.documentos.values() if self._cumple(d, filtro)]

    def find_one(self, filtro: dict) -> dict | None:
        encontrados = self.find(filtro)
        return encontrados[0] if encontrados else None

    def distinct(self, campo: str) -> list:
        return sorted({d[campo] for d in self.documentos.values() if campo in d})

    def replace_one(self, filtro: dict, documento: dict, upsert: bool = False) -> None:
        assert upsert
        self.documentos[filtro["_id"]] = documento


class BaseFalsa(dict):
    def __missing__(self, nombre: str) -> ColeccionFalsa:
        self[nombre] = ColeccionFalsa()
        return self[nombre]


def documento(id, slot, usuario_id=None, lab=(50.0, 10.0, 10.0), **atributos) -> dict:
    doc = {
        "_id": id,
        "slot_outfit": slot,
        "imagen_key": f"prendas/{id}.png",
        "version_esquema": 1,
        "atributos": {
            "tipo": "OTRO",
            "patron": "LISO",
            "textura": "LISO_LIGERO",
            "formalidad": {"min": "CASUAL", "max": "SMART_CASUAL"},
            "clima_apto": ["FRIO", "TEMPLADO", "CALIDO"],
            "color": {"lab": list(lab), "categoria": "GRIS"},
            **atributos,
        },
    }
    if usuario_id:
        doc["usuario_id"] = usuario_id
    return doc


def closet_sin_inferiores(usuario_id: str, superiores: int) -> list[dict]:
    """Sin inferiores no hay outfits actuales: todo outfit valido con la candidata es bueno."""
    return [
        *(
            documento(f"{usuario_id}-ts{i}", "TORSO_SUPERIOR", usuario_id)
            for i in range(superiores)
        ),
        documento(f"{usuario_id}-zapatos", "CALZADO", usuario_id, textura=None),
    ]


def base_con(prendas, catalogo, recomendacion=None) -> BaseFalsa:
    base = BaseFalsa()
    base["prendas"] = ColeccionFalsa(*prendas)
    base["catalogos_marcas"] = ColeccionFalsa(*catalogo)
    base["configuracion"] = ColeccionFalsa(
        {
            "_id": "outfits",
            "dress_codes": {
                "DIA_A_DIA": {"min": "DEPORTIVO", "max": "SMART_CASUAL"},
                "FORMAL": {"min": "FORMAL", "max": "FORMAL"},
            },
        },
        {"_id": "recomendacion", **(recomendacion or {})},
    )
    return base


PANTALON = documento("cat-pantalon", "TORSO_INFERIOR")
COLLAR = documento("cat-collar", "ACCESORIO_CUELLO", textura=None, formalidad=None)


def test_traduce_el_esquema_anidado_de_mongo_al_motor():
    prenda = prenda_desde_documento(
        documento("p1", "TORSO_SUPERIOR", "sub-ana", lab=(50.0, 0.0, 20.0), patron="RAYAS")
    )

    assert prenda.id == "p1"
    assert prenda.slot == Slot.TORSO_SUPERIOR
    assert prenda.patron == Patron.RAYAS
    assert prenda.textura == Textura.LISO_LIGERO
    assert prenda.formalidad == (Formalidad.CASUAL, Formalidad.SMART_CASUAL)
    assert prenda.clima_apto == frozenset(Clima)
    assert round(prenda.color.matiz) == 90


def test_acepta_el_esquema_del_init_local():
    local = {
        "_id": "p2",
        "usuario_id": "sub-ana",
        "tipo": "CAMISA",
        "slot_outfit": "TORSO_SUPERIOR",
        "color": {"lab": {"l": 50.0, "a": 0.0, "b": 20.0}, "categoria": "AMARILLO"},
        "atributos": {
            "textura": "DENIM",
            "patron": "LISO",
            "formalidad": "CASUAL",
            "clima_apto": ["TEMPLADO"],
        },
    }

    prenda = prenda_desde_documento(local)

    assert prenda.formalidad == (Formalidad.CASUAL, Formalidad.CASUAL)
    assert prenda.textura == Textura.DENIM
    assert round(prenda.color.luz) == 50


def test_un_documento_invalido_se_salta_sin_tumbar_el_job():
    roto = {"_id": "roto", "slot_outfit": "TORSO_SUPERIOR", "atributos": {}}

    assert [p.id for p in prendas_validas([roto, PANTALON], "catalogo")] == ["cat-pantalon"]


def test_los_dress_codes_son_los_eventos():
    eventos = eventos_desde(
        {"dress_codes": {"OFICINA": {"min": "SMART_CASUAL", "max": "FORMAL"}, "MAL": {}}}
    )

    assert eventos == {"OFICINA": (Formalidad.SMART_CASUAL, Formalidad.FORMAL)}


def test_el_umbral_sale_de_configuracion_o_del_codigo():
    assert reglas_puente_desde({"prenda_puente": {"umbral_combinaciones_buenas": 7}}).umbral == 7
    assert reglas_puente_desde({"prenda_puente": {"umbral_combinaciones_buenas": "X"}}).umbral == 5
    assert reglas_puente_desde(None).umbral == 5


def test_escribe_el_ranking_de_cada_usuario():
    base = base_con(
        [*closet_sin_inferiores("sub-ana", 5), *closet_sin_inferiores("sub-beto", 2)],
        [PANTALON, COLLAR],
    )

    resultado = rankear_todos(base, AHORA)

    ranking = base[COLECCION_RANKING].documentos
    ana = ranking["sub-ana"]
    assert [p["prenda_id"] for p in ana["puentes"]] == ["cat-pantalon"]
    assert ana["puentes"][0]["combinaciones_buenas"] == 5
    assert ana["umbral"] == 5
    assert ana["calculado_en"] == AHORA
    # Beto solo tiene 2 superiores: el pantalon abre 2 outfits, no llega al umbral.
    assert ranking["sub-beto"]["puentes"] == []
    assert resultado.umbral_alcanzado is True
    assert resultado.usuarios_afectados == 1


def test_el_umbral_de_configuracion_manda():
    base = base_con(
        closet_sin_inferiores("sub-ana", 5),
        [PANTALON],
        recomendacion={"prenda_puente": {"umbral_combinaciones_buenas": 6}},
    )

    resultado = rankear_todos(base, AHORA)

    assert base[COLECCION_RANKING].documentos["sub-ana"]["puentes"] == []
    assert resultado.umbral_alcanzado is False


def test_con_el_catalogo_vacio_se_vacian_los_rankings_viejos():
    base = base_con(closet_sin_inferiores("sub-ana", 5), [])
    base[COLECCION_RANKING] = ColeccionFalsa({"_id": "sub-ana", "puentes": [{"prenda_id": "x"}]})

    resultado = rankear_todos(base, AHORA)

    assert base[COLECCION_RANKING].documentos["sub-ana"]["puentes"] == []
    assert resultado.usuarios_afectados == 0


def test_solo_escribe_en_su_coleccion():
    base = base_con(closet_sin_inferiores("sub-ana", 5), [PANTALON])
    antes = {nombre: dict(c.documentos) for nombre, c in base.items()}

    rankear_todos(base, AHORA)

    for nombre, documentos in antes.items():
        assert base[nombre].documentos == documentos, nombre
