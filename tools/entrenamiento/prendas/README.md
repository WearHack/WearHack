# Clasificador de prendas (issue #69)

MobileNetV3-Small con dos cabezas, **tipo** (21 clases) y **patron** (8), que corre
en el telefono con LiteRT. No hay servicio backend de clasificacion: ver
[ADR 0002](../../../docs/adr/0002-clasificacion-de-prendas-on-device.md).

Aqui solo vive el codigo. Imagenes, recortes, pesos y metricas van **fuera del
repositorio**, en las rutas de `~/.wearhack/prendas.json`:

```json
{"datos": "C:/Users/<usuario>/.wearhack/datos/prendas", "salida": "C:/Users/<usuario>/.wearhack/salidas/prendas"}
```

`configuracion.py` rechaza cualquier ruta que caiga dentro de un repositorio git.

## Fuentes

| Fuente | Para que | Licencia |
|---|---|---|
| Fashionpedia (train2020 y val2020) | Base: tipo y patron, con mascara | Anotaciones CC BY 4.0; cada imagen trae la suya (Flickr: BY, BY-SA, BY-ND...). El manifiesto la guarda por recorte |
| Clothing dataset de Alexey Grigorev | Fotos de prendas sueltas, el dominio de la app. Solo tipo | CC0 1.0 |
| Open Images V7 | Solo si una clase queda corta tras construir el dataset | Anotaciones CC BY 4.0 |

**Prohibidos:** DeepFashion2 y el ecosistema YOLO de Ultralytics (AGPL-3.0).

**Licencias de imagen.** WearHack se monetiza, asi que en los pesos solo entran
fotos con licencia que permite uso comercial. Las NonCommercial y las "all
rights reserved/not found" de Fashionpedia se quedan fuera; son mas de la mitad
de sus recortes. Las NoDerivatives si entran, por decision del equipo. El filtro
es `mapeo.licencia_admitida`:

- `construir_dataset` construye el dataset completo y `entrenar` filtra al leer,
  asi que cambiar la politica no obliga a reconstruir nada.
- El filtro se aplica a entrenamiento, validacion y calibracion INT8.
- La prueba se queda entera: medir no mete esas fotos en los pesos.

El mapeo de etiquetas a los enums de C.18 esta en `mapeo.py`, con sus pruebas.

## Pasos

Los pasos 1 a 3 corren en **Windows con la GPU**. Los pasos 4 y 5 corren en
**WSL**, porque `litert-torch` (antes ai-edge-torch) no publica ruedas para
Windows.

### 0. Entornos (una vez)

En Windows, desde la raiz del repo:

```powershell
uv venv --python 3.12 $HOME\.wearhack\venvs\prendas
uv pip install --python $HOME\.wearhack\venvs\prendas\Scripts\python.exe -r tools/entrenamiento/prendas/requirements-entrenamiento.txt --torch-backend=cu126
```

En WSL (Ubuntu). La Python del sistema es 3.14 y `litert-torch` pide un entorno
aparte, asi que uv baja una 3.12:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
uv venv --python 3.12 ~/.venvs/prendas-exportacion
uv pip install --python ~/.venvs/prendas-exportacion/bin/python -r tools/entrenamiento/prendas/requirements-exportacion.txt --torch-backend=cpu
```

WSL necesita su propia configuracion, con las mismas carpetas vistas desde
`/mnt/c`. Por ejemplo `~/.wearhack/prendas-wsl.json`:

```json
{"datos": "/mnt/c/Users/<usuario>/.wearhack/datos/prendas", "salida": "/mnt/c/Users/<usuario>/.wearhack/salidas/prendas"}
```

### 1. Descargar (Windows)

```powershell
& $HOME\.wearhack\venvs\prendas\Scripts\python.exe tools/entrenamiento/prendas/descargar_fuentes.py
```

Son unos 4,1 GB. Si se corta, se relanza: reanuda y no repite lo hecho.
Escribe `datos/fuentes.json` con el SHA-256 de cada archivo.

### 2. Construir el dataset (Windows)

```powershell
& $HOME\.wearhack\venvs\prendas\Scripts\python.exe tools/entrenamiento/prendas/construir_dataset.py
```

Tarda entre 30 y 60 minutos. Mira `salida/dataset/resumen.json`: si una clase
de tipo tiene menos de unos 300 recortes de entrenamiento, es candidata a
completarse con Open Images.

### 3. Entrenar (Windows, GPU)

```powershell
& $HOME\.wearhack\venvs\prendas\Scripts\python.exe tools/entrenamiento/prendas/entrenar.py --procesos 2
```

Con 8 GB de RAM, mas de 2 procesos de carga se queda sin memoria. Si la GPU se
queda corta, usa `--lote 64`. Escribe `salida/modelo/pesos.pt` (la mejor epoca
en validacion), `etiquetas.json` y `entrenamiento.json`.

### 4. Exportar (WSL)

```bash
WEARHACK_PRENDAS_CONFIG=~/.wearhack/prendas-wsl.json ~/.venvs/prendas-exportacion/bin/python tools/entrenamiento/prendas/exportar.py
```

Escribe tres variantes en `salida/modelo/`: FP32 (la referencia), INT8 por
canal, calibrado con 25 recortes de entrenamiento por tipo, y FP16 (pesos en
FP16). La entrada es `(1, 224, 224, 3)` RGB en `[0, 255]`, porque la normalizacion
va dentro del modelo.

### 5. Evaluar (WSL)

```bash
WEARHACK_PRENDAS_CONFIG=~/.wearhack/prendas-wsl.json ~/.venvs/prendas-exportacion/bin/python tools/entrenamiento/prendas/evaluar.py
```

Compara cada `.tflite` con PyTorch en validacion y en prueba: exactitud por
cabeza, por fuente y por clase, tamano frente al presupuesto de 15 MB y latencia
con un hilo. Escribe `evaluacion.json` e `informe.md`.

**Criterio:** INT8 vale si ninguna cabeza cae mas de 1 punto en prueba. Si
alguna cae mas, la escalera es:

1. INT8 por canal, que es lo que se exporta por defecto.
2. QAT. **No esta automatizado:** solo merece la pena si la caida es pequena y
   FP16 no cabe en el presupuesto.
3. FP16, que se exporta siempre y es la que recomienda `evaluar` cuando INT8 no
   cumple.

### 6. Al cliente

La variante recomendada se copia a `client/assets/models/clasificador_prenda.tflite`
**sin commitearla**: esa carpeta va vacia en git. Su SHA-256 y su origen van en
`client/assets/models/README.md` y en `docs/procedencia-datos-wearhack.md`.

## Pruebas

```powershell
py -3.12 -m unittest discover -s tools/entrenamiento/prendas -v
```

Solo usan la libreria estandar: cubren el mapeo de etiquetas y la configuracion.
