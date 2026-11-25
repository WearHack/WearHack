# Modelos on-device

Esta carpeta va vacia en git. Los modelos pesan decenas de megabytes y no tienen
por que vivir en el historial.

La clasificacion de prendas corre **en el dispositivo**, no en el backend. No
existe ni va a existir un servicio de clasificacion: la foto de una prenda no
sale del telefono, y solo se sube la imagen ya procesada.

## Que va aqui

| Archivo | Para que | Notas |
|---|---|---|
| `u2netp.tflite` | Quitar el fondo de la prenda | Version ligera de U^2-Net |
| `clasificador_prenda.tflite` | Tipo (21 clases) y patron (8) | MobileNetV3-Small de dos cabezas, pesos en FP16. La textura sera una tercera cabeza mas adelante |

La deteccion y el recorte de rostro no llevan modelo propio: los hace ML Kit,
que trae el suyo dentro del paquete.

## Por que FP16 y por que multi-head

El plan era INT8: reduce el modelo a la cuarta parte y corre en el acelerador del
telefono. Pero la cuantizacion INT8 tras el entrenamiento hundio la exactitud unos
30 puntos por cabeza (MobileNetV3 cuantiza mal sin QAT), y el limite era 1. En
FP16 no pierde nada, pesa 3,1 MB y el delegado de GPU de LiteRT lo ejecuta en
media precision. Las cifras estan en `docs/procedencia-datos-wearhack.md`.

Un solo modelo con varias cabezas en vez de un modelo por atributo significa
una carga de pesos en vez de varias.

## Entrada y salidas

- **Entrada:** `(1, 224, 224, 3)` float32, RGB en `[0, 255]`, sin normalizar: la
  normalizacion va dentro del modelo. La prenda ya recortada se rellena a
  cuadrado con blanco y se escala a 224 con interpolacion bilineal, igual que en
  el entrenamiento.
- **Salidas:** dos tensores de logits. Se distinguen por su tamano, no por el
  orden: 21 son de tipo y 8 de patron. El orden de las clases es el de `TIPOS`
  y `PATRONES` en `tools/entrenamiento/prendas/mapeo.py`; el entrenamiento
  tambien lo deja en `etiquetas.json`, junto a los pesos.

## Carga secuencial

Los interpretes se cargan y se liberan **de uno en uno**, nunca a la vez.
u2netp y el clasificador juntos en memoria sacan del proceso a los telefonos
con poca RAM, que son justo los que hay que soportar. Ver `GarmentPipeline`.

## De donde salen

`clasificador_prenda.tflite` se genera con `tools/entrenamiento/prendas/` (ver su
README). La version actual es `prendas-v1`, la variante `clasificador_prenda_fp16.tflite`:

```
SHA-256  bb0ae7eb9dbb56723878f366ba5e16de32f2a05d2bb19361ea5e0fc638a23696
```

Para comprobarla en PowerShell:

```powershell
Get-FileHash client/assets/models/clasificador_prenda.tflite -Algorithm SHA256
```

Aun no esta publicado en ningun sitio compartido: hoy solo lo tiene quien lo
entreno. Los datos y licencias de origen estan en `docs/procedencia-datos-wearhack.md`.

`u2netp.tflite` son los pesos oficiales de U^2-Net (`u2netp.pth`, 4,7 MB,
Apache 2.0, sin reentrenar), exportados con `tools/entrenamiento/fondo/` (ver su
README). Es la variante `u2netp_fp16.tflite`, 2,5 MB:

```
SHA-256  69bbee91b885fc2df8182168c95293732694ed411b5b2cbdbd2f6ae1ab142eee
```

Entrada `(1, 320, 320, 3)` float32, RGB en `[0, 255]`, la foto entera escalada
sin conservar la proporcion; la normalizacion va dentro. Salida `(1, 320, 320, 1)`,
la probabilidad de primer plano. El preproceso y la mascara estan en
`lib/core/clasificacion/removedor_fondo.dart`.

Tampoco esta publicado en ningun sitio compartido.

Los hashes anteriores identifican los archivos de origen. Si el runtime indica
`Input tensor ... lacks data`, usa
`tools/entrenamiento/prendas/compatibilizar_tflite.py ORIGINAL COPIA` desde la
raíz del repo para integrar los pesos de cada modelo. Conserva los originales y
coloca las copias en esta carpeta con los nombres indicados arriba.
