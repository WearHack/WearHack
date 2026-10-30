# Analisis de normalizacion de color (issue #66)

Implementa el protocolo de
[`docs/protocolo-normalizacion-colorimetria.md`](../../docs/protocolo-normalizacion-colorimetria.md):
compara las tecnicas **T0, T1, T2 y REF** con las metricas **M1-M6** sobre las fotos de
la sesion de calibracion (#65) y da un **veredicto** contra los criterios fijados de
antemano.

La segmentacion y el muestreo son los del servicio de Colorimetria (`app.extraccion`),
con los parametros del artefacto de centroides: lo que se mide aqui es lo que el
producto hara.

**Ninguna foto, tono de piel ni resultado va en este repositorio.** Todo vive en la
boveda, en las rutas de una configuracion local. Las pruebas fabrican sus imagenes.

## Entorno

El mismo del servicio de Colorimetria (Python 3.12, MediaPipe, numpy, Pillow):

```bash
uv venv -p 3.12 ~/.wearhack/venvs/colorimetria
VIRTUAL_ENV=~/.wearhack/venvs/colorimetria uv pip install -r services/colorimetria/pyproject.toml --extra dev
```

Todo se corre desde esta carpeta (`analisis/normalizacion/`).

## 1. Validar la tarjeta (antes de la sesion)

La tarjeta del equipo es un juego generico de blanco, gris 18 % y negro, sin
especificacion de neutralidad. Antes de usarla como referencia:

1. Fotografia las tres tarjetas juntas con el celular bajo dos o tres luces distintas
   (ventana, bombilla calida, luz blanca de oficina). Mate, sin brillos encima, sin
   que el blanco se queme.
2. Marca los parches. Por foto, dos clics en esquinas opuestas de cada parche:
   blanco, gris y negro.

   ```bash
   python -m normalizacion.marcar_tarjeta --cajas RUTA_FUERA_DEL_REPO/cajas.json fotos/*.jpg
   ```

3. Valida:

   ```bash
   python -m normalizacion.validar_tarjeta --cajas RUTA_FUERA_DEL_REPO/cajas.json fotos/*.jpg
   ```

   Si el blanco y el gris "ven" luces que difieren mas de 3 grados, alguno tiene tinte y
   la tarjeta no sirve como referencia. El limite es provisional: el protocolo no lo fija.

## 2. Configuracion (una vez)

`~/.wearhack/normalizacion.json` (o `WEARHACK_NORMALIZACION_CONFIG`), fuera del repo:

```json
{
  "lotes": "<carpeta de la boveda con los lotes que deja tools/captura/importar_lote.py>",
  "modelos_mediapipe": "<carpeta con face_landmarker.task y selfie_multiclass_256x256.tflite>",
  "artefacto": "<centroides-4-estaciones-v1.json>",
  "salida": "<carpeta de resultados, en la boveda>",
  "tarjetas": "<tarjetas.json con las cajas de las tomas R1>",
  "grupos_tono": "<grupos_tono.json: {\"P1\": 3, ...}, tono Monk de 1 a 10>",
  "mst_e": {"imagenes": "<carpeta>", "etiquetas": "<csv con columnas archivo,monk>"}
}
```

`tarjetas`, `grupos_tono` y `mst_e` son opcionales. Sin `grupos_tono` la equidad (M5)
queda sin evaluar; sin `mst_e`, M4 se omite. Los tonos de piel son datos sensibles:
solo en la boveda.

## 3. Analizar la sesion

```bash
python -m normalizacion.marcar_tarjeta --sesion   # las tomas R1 sin marcar
python -m normalizacion.extraer                   # mediciones.csv
python -m normalizacion.analizar                  # resultados.json e informe.md
```

`--incluir-d3` en `extraer` mete el celular reservado: solo para la validacion final,
despues de elegir la tecnica (protocolo, seccion 7). Los umbrales de calidad para M6
se pasan a `analizar` (`--max-quemados`, `--max-negros`, `--min-nitidez`,
`--min-ancho`); sin ellos se reportan las medianas.

## Que hace cada tecnica

Todas estiman el color de la luz y corrigen con von Kries en RGB lineal.

| Tecnica | Luz estimada con |
|---|---|
| T0 | Nada: supone luz neutra. Linea base |
| T1 | El blanco del ojo (mascara de esclerotica del segmentador), sin sombras ni reflejos |
| T2 | El 1 % de pixeles mas brillantes de piel y ojos sin saturar (brillos especulares) |
| REF | El parche gris de la tarjeta en la foto completa. Solo tomas `R1` marcadas |

## Decisiones que hay que leer con el protocolo

- **M1 y M2** comparan todas las parejas de fotos de la misma persona con luz normal
  (`VEN`, `LEDC`, `LEDF`), de cualquier celular y repeticion.
- **M2** se calcula con la frontera del protocolo (la mediana del grupo) y con la
  decision de los centroides `4-estaciones-v1`, que no existian al escribirlo. El
  veredicto usa la del protocolo; la otra se reporta.
- **REF no se puede elegir**: es el mejor caso, con la tarjeta en el encuadre, no una
  opcion del producto.
- **Obligatorios**: el criterio principal y el de equidad. El secundario (M1 de piel,
  p90, 30 % menor que T0) se reporta.
- **Cobertura**: la fraccion de tomas en que la tecnica pudo estimar la luz. Por debajo
  del 90 % no cumple: una tecnica que solo funciona en fotos faciles parece mejor de
  lo que es.

## Limites conocidos

- **T2 es la aproximacion simple** del modelo dicromatico. Si promete, se puede ajustar
  el plano dicromatico completo.
- **T3 y T4 quedan fuera de #66.** Si ninguna de T0-T2 cumple, el informe lo dice.
- **La geografia no se mide**: la sesion es en una sola ciudad y una tarde (ver #97).
- **M4 necesita MST-E** y leer antes sus terminos de uso.
- Con un juego de tarjetas generico no hay parches de piel de reflectancia conocida:
  se mide estabilidad, no exactitud.

## Pruebas

```bash
python -m pytest
```

Sinteticas: dominantes de color conocidas, una tarjeta fabricada, ΔE00 contra los
pares publicados de Sharma et al. (2005) y mediciones inventadas con un ganador
conocido para el veredicto. No prueban MediaPipe sobre rostros reales.
