# tools/iscc-nbs: tabla de categorías de color de prenda (#58)

Genera `client/assets/color/iscc_nbs.json` y su copia en el Core,
`services/core/src/main/resources/colores/iscc_nbs.json`. Las dos tienen que ser iguales y una
prueba del Core falla si se separan. La app asigna cada color al bloque ISCC-NBS más cercano
(ΔE00) y le pone la categoría del bloque.

| Archivo | Qué es |
|---|---|
| `centroides_nist_1958.csv` | Los 267 centroides en Munsell, transcritos de la tabla 1 de Kelly (1958), *Central Notations for the Revised ISCC-NBS Color-Name Blocks*, J. Res. NBS 61(5), RP2911 ([nvlpubs.nist.gov](https://nvlpubs.nist.gov/nistpubs/jres/61/jresv61n5p427_A1b.pdf)). La columna `nota` marca lo que el escaneo no deja leer bien |
| `generar_tabla.py` | Munsell → Lab D65 con colour-science (no munsellinterpol, que es GPL) y reglas nombre → categoría (`REGLAS`) |

Las 20 categorías son las de `CategoriaColor` del Core.

## Regenerar

Solo hace falta si cambia el CSV o una regla. CI no lo corre: necesita scipy.

```bash
uv venv && uv pip install colour-science==0.4.7 scipy
uv run python tools/iscc-nbs/generar_tabla.py              # escribe el JSON
uv run python tools/iscc-nbs/generar_tabla.py --comprobar  # falla si el JSON no coincide
cd client && flutter test test/categoria_color_test.dart
```

## Decisiones

- Los centroides no se mueven: son el estándar. Lo que cambia con las correcciones de los
  usuarios es la categoría de un bloque: con 10 correcciones o más y al menos el 70 % de
  acuerdo. Lo decide la tarea `AjusteCategoriasColor` del Core, una vez al día, y lo guarda en
  `ajustes_categoria_color`. La app lo baja de `GET /api/v1/closet/colores/ajustes` y lo
  aplica sobre esta tabla. Para cambiar una categoría a mano, para todos, se cambia `REGLAS`
  y se regenera.
- El `+`/`-` del original (incertidumbre en el decimal siguiente) se descarta.
- La renotación Munsell no llega por debajo de V = 1. En los cuatro negros con V < 1, la
  cromaticidad se toma de V = 1 y la luminancia del valor real. Quedan anotados en `ajustes`.
- Iluminante C → D65 con Bradford, y Lab con el blanco D65 de la app (`conversion.dart`).
