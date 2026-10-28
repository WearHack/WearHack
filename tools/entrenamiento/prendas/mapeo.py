"""Mapeo de las etiquetas de las fuentes a los enums de WearHack (respuestas C.18).

Es la parte del entrenamiento que mas pesa en el resultado y la que mas facil
se equivoca en silencio, asi que vive sola, sin dependencias, y con tests.

- `tipo`: las 21 clases que salen del clasificador. `JOYERIA` es manual
  (Fashionpedia no la tiene) y guantes, medias, calentadores y paraguas quedan
  fuera del MVP.
- `patron`: los 8 de C.18, desde los atributos de patron de Fashionpedia.
  Una prenda sin atributo de patron **no** es lisa: queda sin etiqueta de
  patron. Solo cuenta como `LISO` si esta anotada como "plain".
"""

from __future__ import annotations

TIPOS = (
    "CAMISA",
    "CAMISETA",
    "SUETER",
    "CARDIGAN",
    "CHAQUETA",
    "ABRIGO",
    "CHALECO",
    "PANTALON",
    "SHORT",
    "FALDA",
    "VESTIDO",
    "ENTERIZO",
    "CALZADO",
    "GAFAS",
    "SOMBRERO",
    "ACCESORIO_CABELLO",
    "CORBATA",
    "BUFANDA",
    "RELOJ",
    "CINTURON",
    "BOLSO",
)

PATRONES = (
    "LISO",
    "RAYAS",
    "CUADROS",
    "PUNTOS",
    "FLORAL",
    "ANIMAL",
    "GEOMETRICO",
    "OTRO_ESTAMPADO",
)

# Categoria de Fashionpedia -> tipo. Las que no estan se descartan.
TIPO_DESDE_FASHIONPEDIA = {
    "shirt, blouse": "CAMISA",
    "top, t-shirt, sweatshirt": "CAMISETA",
    "sweater": "SUETER",
    "cardigan": "CARDIGAN",
    "jacket": "CHAQUETA",
    "vest": "CHALECO",
    "pants": "PANTALON",
    "shorts": "SHORT",
    "skirt": "FALDA",
    "coat": "ABRIGO",
    "cape": "ABRIGO",  # C.18: ABRIGO incluye capa
    "dress": "VESTIDO",
    "jumpsuit": "ENTERIZO",
    "glasses": "GAFAS",
    "hat": "SOMBRERO",
    "headband, head covering, hair accessory": "ACCESORIO_CABELLO",
    "tie": "CORBATA",
    "watch": "RELOJ",
    "belt": "CINTURON",
    "shoe": "CALZADO",
    "bag, wallet": "BOLSO",
    "scarf": "BUFANDA",
}

# Categorias de prenda completa que se descartan a proposito (fuera del MVP).
# Las partes (manga, cuello, bolsillo...) se descartan por no ser prenda.
DESCARTADAS_FASHIONPEDIA = {"glove", "leg warmer", "tights, stockings", "sock", "umbrella"}

# Atributos de los supergrupos "textile pattern" y "animal" de Fashionpedia ->
# patron. Los estampados animales viven en "animal", no en "textile pattern".
PATRON_DESDE_FASHIONPEDIA = {
    "plain (pattern)": "LISO",
    "stripe": "RAYAS",
    "check": "CUADROS",
    "houndstooth (pattern)": "CUADROS",
    "dot": "PUNTOS",
    "floral": "FLORAL",
    "plant": "FLORAL",
    "leopard": "ANIMAL",
    "cheetah": "ANIMAL",
    "snakeskin (pattern)": "ANIMAL",
    "zebra": "ANIMAL",
    "giraffe": "ANIMAL",
    "peacock": "ANIMAL",
    "geometric": "GEOMETRICO",
    "chevron": "GEOMETRICO",
    "argyle": "GEOMETRICO",
    "herringbone (pattern)": "GEOMETRICO",
    "fair isle": "GEOMETRICO",
    "abstract": "OTRO_ESTAMPADO",
    "cartoon": "OTRO_ESTAMPADO",
    "letters, numbers": "OTRO_ESTAMPADO",
    "camouflage": "OTRO_ESTAMPADO",
    "paisley": "OTRO_ESTAMPADO",
    "toile de jouy": "OTRO_ESTAMPADO",
}

SUPERGRUPOS_DE_PATRON = ("textile pattern", "animal")

# Clase del Clothing dataset de Grigorev -> tipo. Las que faltan se descartan:
# "Outwear" mezcla chaquetas y abrigos, "Body" no tiene tipo en C.18, y "Not
# sure", "Other" y "Skip" no son etiquetas.
TIPO_DESDE_GRIGOREV = {
    "T-Shirt": "CAMISETA",
    "Longsleeve": "CAMISETA",
    "Polo": "CAMISETA",
    "Undershirt": "CAMISETA",
    "Hoodie": "CAMISETA",  # C.18: CAMISETA incluye buzo
    "Top": "CAMISETA",
    "Shirt": "CAMISA",
    "Blouse": "CAMISA",
    "Blazer": "CHAQUETA",  # C.18: la diferencia con la chaqueta es de formalidad
    "Pants": "PANTALON",
    "Shorts": "SHORT",
    "Skirt": "FALDA",
    "Dress": "VESTIDO",
    "Shoes": "CALZADO",
    "Hat": "SOMBRERO",
}


# Licencias de imagen que no entran en los pesos: WearHack se monetiza, asi que
# nada NonCommercial, y nada sin licencia conocida. Las NoDerivatives si entran
# (decision del equipo, ver la procedencia). Se comparan como subcadena con el
# nombre que trae cada imagen de Fashionpedia.
LICENCIAS_EXCLUIDAS = ("NonCommercial", "all rights reserved")


def licencia_admitida(nombre: str) -> bool:
    """Si una imagen con esta licencia puede usarse para entrenar o calibrar."""
    return not any(excluida.lower() in nombre.lower() for excluida in LICENCIAS_EXCLUIDAS)


def patron_de_atributos(nombres: list[str]) -> str | None:
    """Patron de una prenda a partir de sus atributos de Fashionpedia.

    None si no tiene atributo de patron o si sus patrones se contradicen
    (rayas y floral a la vez): mejor sin etiqueta que con una inventada.
    """
    patrones = {PATRON_DESDE_FASHIONPEDIA[n] for n in nombres if n in PATRON_DESDE_FASHIONPEDIA}
    return patrones.pop() if len(patrones) == 1 else None


def comprobar_ontologia(categorias: list[str], patrones: list[str]) -> list[str]:
    """Problemas entre los mapeos y la ontologia real descargada.

    `categorias`: nombres de las categorias de prenda completa (no partes).
    `patrones`: nombres de los atributos de patron (`SUPERGRUPOS_DE_PATRON`).
    """
    problemas = []
    for c in categorias:
        if c not in TIPO_DESDE_FASHIONPEDIA and c not in DESCARTADAS_FASHIONPEDIA:
            problemas.append(f"categoria sin mapear ni descartar: {c!r}")
    for c in TIPO_DESDE_FASHIONPEDIA:
        if c not in categorias:
            problemas.append(f"categoria mapeada que no existe: {c!r}")
    for p in patrones:
        if p not in PATRON_DESDE_FASHIONPEDIA:
            problemas.append(f"patron sin mapear: {p!r}")
    for p in PATRON_DESDE_FASHIONPEDIA:
        if p not in patrones:
            problemas.append(f"patron mapeado que no existe: {p!r}")
    return problemas
