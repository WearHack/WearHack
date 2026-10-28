# calibracion

Centroides de 4 estaciones con Deep Armocromia (issue #68). Solo para el MVP
academico: el dataset deriva de CelebA, que prohibe explotar comercialmente los
datos derivados. Ver `docs/procedencia-datos-wearhack.md`.

**Ningun rostro, variable derivada ni centroide va en este repositorio.** Los
scripts se niegan a leer o escribir rutas que esten dentro de uno.

No entra en la imagen del servicio: el Dockerfile solo copia `app/`. Lo que si
usa el servicio es lo que importa de alli: `app/extraccion/` (segmentacion y
muestreo) y `app/clasificador.py`.

## Una vez

Python 3.12 (MediaPipe no tiene ruedas para 3.14) y un venv fuera del repo:

```bash
uv venv -p 3.12 ~/.wearhack/venvs/colorimetria
VIRTUAL_ENV=~/.wearhack/venvs/colorimetria uv pip install -r services/colorimetria/pyproject.toml --extra dev --extra calibracion
```

Modelos oficiales de MediaPipe (Apache 2.0) en una carpeta fuera del repo:

```bash
curl -LO https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/latest/face_landmarker.task
curl -LO https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_multiclass_256x256/float32/latest/selfie_multiclass_256x256.tflite
```

Los hashes de los que se usaron quedan en el artefacto (`segmentacion.modelos`).

Rutas en `~/.wearhack/entrenamiento.json` (o la variable
`WEARHACK_ENTRENAMIENTO_CONFIG`):

```json
{
  "deep_armocromia": "<carpeta con train/ y test/, tal como la entregan los autores>",
  "modelos_mediapipe": "<carpeta con los dos modelos>",
  "salida": "<carpeta de resultados, en la boveda>"
}
```

## Pasos

Desde `services/colorimetria/`, con el venv:

```bash
python -m calibracion.extraer --procesos 2                   # ~15 min, 4.920 imagenes
python -m calibracion.extraer --perturbaciones --procesos 2  # ~15 min, test x 6
python -m calibracion.calibrar                               # minutos
```

Cada proceso de MediaPipe ocupa unos 500 MB: con poca RAM libre, pocos procesos.

| Salida | Que es |
|---|---|
| `manifiesto.json`, `manifiesto.sha256` | Conteos, SHA-256 de cada imagen y hash global del dataset |
| `regiones.csv`, `regiones_perturbadas.csv` | Color de cada region con cada variante de muestreo |
| `centroides-4-estaciones-v1.json` | El artefacto: estandarizacion, variables y centroides por capa, muestreo, parametros y hashes |
| `metricas.json`, `informe.md` | Validacion cruzada de cada variante y metricas de prueba |

## Que se decide y como

- **Muestreo**: entre media sin recorte (como la tesis de Dinh) y mediana con
  recorte por percentil de L*. La variante se elige por validacion cruzada de 5
  pliegues **solo en train**.
- **Variables de cada capa**: busqueda voraz hacia delante con la misma validacion.
- **Prueba**: se usa una vez, al final. Una imagen no clasificable cuenta como error.
- **Semilla**: 42.

## Proxies, no metricas finales

- **Equidad**: bandas de ITA calculadas con la piel medida, no la escala Monk.
  Deep Armocromia no trae anotacion Monk, y el ITA de una foto depende de la luz.
- **Estabilidad**: la misma imagen con exposicion, balance de blancos, JPEG y
  escala alterados. La estabilidad por persona real es la etapa 0, con las fotos
  del equipo.
- **Diferencia con el producto**: aqui no hay normalizacion de luz (A.9 sin
  decidir), solo el nivel 0 (sRGB a Lab D65).
