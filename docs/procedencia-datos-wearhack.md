# Registro de procedencia de datos y modelos — WearHack

_Creado: 2026-10-01 · Estrategia: MVP exclusivamente académico (ver stack, sección 6)._

## Para qué sirve

Cada artefacto que el producto usa (modelos, centroides, umbrales, parámetros) se anota aquí con los datos con que se construyó y su licencia. Así, si WearHack pasa a lo comercial, se sabe exactamente qué reconstruir.

## Reglas

1. **Anotar antes de usar.** Ningún artefacto entra al producto sin su fila aquí.
2. **Una fila por versión.** Si se recalibra o reentrena, nueva fila.
3. **Cada licencia se respeta por separado**: "académico" no autoriza todo. Revisar la columna de restricciones antes de usar un dataset.
4. **Pitch**: no mostrar a marcas ni inversionistas artefactos marcados "No" en uso comercial.
5. Las fuentes de datos se guardan en la bóveda, nunca en el repositorio.

## Estados

- **Planeado**: previsto, todavía no construido.
- **En uso**: está en el MVP.
- **Reemplazado**: sustituido por una versión posterior.

## Artefactos

| Artefacto | Versión | Datos de origen | Licencia de los datos | Restricciones relevantes | ¿Uso comercial? | Al pasar a comercial | Estado |
|---|---|---|---|---|---|---|---|
| Centroides de temporada (4 estaciones) | `4-estaciones-v1` (2026-10-26) | Deep Armocromia, conjunto de entrenamiento (4.008 imágenes; hash del manifiesto `fc730b52…b9fd`), pasado por el pipeline propio (MediaPipe + muestreo). Métricas abajo | Investigación; derivado de CelebA | CelebA prohíbe explotar comercialmente datos derivados | **No** | Reconstruir con el enfoque propio (puntuaciones normalizadas, drapeado virtual, correcciones de usuarios con consentimiento) | En uso en el endpoint de colorimetría (#29), publicado en la colección `centroides_colorimetria` de Mongo. El artefacto no va en la imagen ni en el repositorio |
| Centroides de temporada (12 subtipos) | — | Deep Armocromia | Igual | Igual | **No** | Igual | Planeado (etapa 2) |
| Clasificador de prendas (MobileNetV3-Small, cabezas de tipo y patrón) | `prendas-v1` (2026-10-27), FP16, SHA-256 `bb0ae7eb…3696` | **Fashionpedia** train2020 (33.281 recortes) + **Clothing dataset** de Grigorev, commit `7ed86a9` (4.435). Solo imágenes con licencia comercial: se excluyen las NonCommercial y las "all rights reserved/not found". Open Images no hizo falta. Pesos de ImageNet de timm (`mobilenetv3_small_100.lamb_in1k`). DeepFashion2 retirado. Métricas abajo | Fashionpedia: anotaciones CC BY 4.0; imágenes de los recortes usados: BY-ND 11.158, BY 9.871, BY-SA 8.799, Unsplash 2.309, Pexels 880, Burst 137, dominio público 78, Freestocks 49. Clothing dataset: CC0 1.0 | Atribución. **Las BY-ND entran por decisión del equipo (2026-10-27)**: falta confirmar que unos pesos entrenados no son obra derivada. Revisar los términos de Unsplash y Pexels sobre entrenar modelos. No usar el ecosistema YOLO de Ultralytics (AGPL-3.0) | **Sí, con atribución** (sujeto a las revisiones de BY-ND, Unsplash y Pexels) | Mantener con atribución, o reentrenar sin BY-ND si la revisión sale en contra (el filtro está en `mapeo.licencia_admitida`) | Construido. Pendiente de integrar en el cliente. Artefacto fuera del repositorio |
| Cabeza de textura (futura) | — | Correcciones de textura de los usuarios, con consentimiento | Propias | — | Sí | Sin cambios | Planeado (después del MVP) |
| Población de referencia de colorimetría (percentiles de subtono, contraste y valor) | — | **FairFace** | CC BY 4.0 (imágenes de Flickr con CC BY y CC BY-SA) | Atribución. Sus etiquetas de grupo racial son datos sensibles: solo para balancear la muestra, nunca como dato del producto. Baja resolución y luz variada: sirve para estadísticas de población, no para calibrar color fino | Sí, con atribución | Sin cambios | Planeado |
| Anotaciones Monk de FairFace | — | Anotación propia con la escala Monk (CC BY 4.0) | Propias | Atribuir la escala | Sí | Sin cambios | Planeado |
| Segmentación de prenda (u2netp) | MVP: pesos oficiales | DUTS (entrenamiento original) | Código y pesos Apache 2.0 según el repositorio; el autor pide revisar las licencias de los datasets de entrenamiento, que no controla | Riesgo bajo a medio | Probablemente sí (no resuelto jurídicamente) | **Reentrenar** con máscaras CC BY (Fashionpedia, Open Images) antes de lo comercial, o antes si el recorte falla con prendas sueltas. Hay que mezclar fuentes o generar máscaras de prendas sueltas | En uso en el MVP (planeado) |
| Segmentación y landmarks faciales (MediaPipe) | `face_landmarker.task` (float16, SHA-256 `64184e22…9ff`) y `selfie_multiclass_256x256.tflite` (float32, SHA-256 `c6748b12…e0e0`), descargados el 2026-10-26 | Modelos oficiales de Google | Apache 2.0 | — | Sí | Sin cambios | En uso en la calibración y en el servicio (#29): la imagen los trae por versión fija con checksum, y el servicio no responde si no coinciden con los del artefacto |
| Detección facial en el cliente (ML Kit) | — | Servicio de Google | Términos de ML Kit | Depende de Google Play Services | Sí (según sus términos) | Sin cambios | Planeado |
| Elección de la técnica de normalización | — | Fotos del equipo (consentimiento de calibración) + MST-E solo para evaluar | Propias + MST-E (educativo o de investigación, sin entrenamiento) | MST-E no entrena ni se redistribuye | Sí, con matiz: la técnica es un algoritmo, no un modelo entrenado. Validar | Revalidar con datos propios | Planeado |
| Umbrales de calidad y percentiles de muestreo | — | Fotos del equipo | Propias, con consentimiento | — | Sí | Revalidar con datos de uso real | Planeado |
| Centroides de color de prenda | — | **ISCC-NBS** (centroides publicados por el NBS en 1958, tomados de la fuente NIST, no del paquete de R `munsellinterpol`, que es GPL), nivel 3 (267 bloques) con asignación por ΔE00 y tabla de traducción a 20 categorías en español. Los centroides no se mueven; la tabla de traducción se ajusta por mayoría de correcciones de usuarios (≥ 10, ≥ 70 %) | Publicación del gobierno de EE. UU. (dominio público allá); los valores numéricos son datos | — | Sí | Sin cambios | Planeado |
| Método del clasificador jerárquico | — | Tesis de Dinh (Leiden, 2026): método, no datos | Las ideas no tienen licencia | — | Sí | Sin cambios | Planeado |

## Fuentes de datos

| Fuente | Licencia y términos | Uso permitido en WearHack | Dónde se guarda | Acceso solicitado |
|---|---|---|---|---|
| Deep Armocromia | Investigación (por confirmar con los autores) | Centroides y evaluación del MVP académico | Bóveda. **Pendiente (2026-10-26)**: la copia recibida está sin cifrar en el disco de un integrante; moverla a la bóveda | Recibido (2026-10-26): 4.920 imágenes RGB (4.008 entrenamiento / 912 prueba) y máscaras de facer de parte del entrenamiento, que no se usan |
| Fashionpedia | **Verificado (2026-10-01)**: anotaciones, ontología y sitio CC BY 4.0; las imágenes no son de Fashionpedia y se rigen por los términos de Flickr, Unsplash, Burst, Freestocks, Kaboompics y Pexels (quien usa el dataset asume la responsabilidad) | Base del clasificador de tipo y patrón; máscaras para un futuro reentrenamiento de u2netp | Disco local del equipo de entrenamiento, fuera del repositorio | Descarga abierta |
| DeepFashion2 | Acuerdo firmado (revisado el 2026-10-01): solo investigación no comercial; las imágenes no son de los autores; no explotar comercialmente imágenes **ni datos derivados**; no copiar, publicar ni distribuir, salvo copias internas en **un solo sitio** de la misma organización; el acceso es revocable | Entrenamiento del clasificador de prendas en el MVP académico | **Un solo equipo** (el de entrenamiento), fuera del repositorio. No se copia a portátiles del equipo, a la carpeta institucional ni a CI | **Retirado del plan (2026-10-01)**: el acuerdo se firmó, pero no se usará para no contaminar el registro |
| Clothing dataset (Alexey Grigorev) | Uso libre para cualquier propósito, incluido el comercial | Clasificador de prendas (dominio de prendas sueltas) | Disco local del equipo de entrenamiento | Descarga abierta (GitHub o Kaggle) |
| Open Images V7 | Anotaciones CC BY 4.0; imágenes listadas CC BY 2.0, sin garantía de Google por imagen | Solo las clases de prenda que falten (calzado, accesorios); descargar solo esas clases, no los 561 GB completos | Disco local del equipo de entrenamiento | Descarga abierta |
| FairFace | CC BY 4.0 | Población de referencia de colorimetría y evaluación de equidad (con anotación Monk propia) | Bóveda (son rostros) | Descarga abierta |
| Escala Monk (MST) | CC BY 4.0 | Esquema de tonos para equidad y metadatos | — | Pública |
| EasyPortrait | Variante de CC BY-SA 4.0 con texto propio: **leer antes de usar** | Solo validar la segmentación facial de MediaPipe, sin entrenar | Bóveda (son rostros) | Pendiente: leer la licencia |
| ISCC-NBS | Publicación del NBS/NIST (gobierno de EE. UU.) | Centroides de las categorías de color de prenda | Repositorio (son solo valores numéricos) | Pública (nvlpubs.nist.gov) |
| MST-E | Educativo o de investigación; sin entrenamiento; copyright de TONL; sin redistribución (revisado el 2026-10-01) | Solo evaluación | Bóveda | Descarga abierta |
| Casual Conversations v2 | Acuerdo de licencia; orientado a evaluación; entrenamiento solo con ciertas etiquetas | Evaluación de robustez y equidad | Bóveda | Pendiente |
| CelebAMask-HQ | Investigación no comercial | Opcional: validar la segmentación | Bóveda | No solicitado |
| Fotos de calibración del equipo | Consentimiento específico de calibración | Estabilidad, normalización y umbrales | Bóveda | — |

## Métricas por versión

### Centroides `4-estaciones-v1` (2026-10-26, issue #68)

Calculados con `services/colorimetria/calibracion/` (semilla 42). Todas las elecciones (muestreo y variables de cada capa) se hicieron con validación cruzada de 5 pliegues sobre el conjunto de entrenamiento; el de prueba (912 imágenes) se usó una sola vez.

| Métrica (RNF07, E.29) | Prueba | IC 95 % | Línea base publicada |
|---|---|---|---|
| 4 estaciones | 55,9 % | 52,6-59,2 % | ~54 % |
| Subtono | 70,9 % | 68,0-74,0 % | ~70 % |
| Contraste | 77,3 % | 74,5-80,2 % | ~76 % |
| Dos primeras opciones | 81,6 % | 78,9-84,0 % | — |

- **Cobertura**: 99,8 % (8 de 4.920 imágenes sin rostro detectado). Las no clasificables cuentan como error.
- **Muestreo elegido**: media sin recorte para piel y cabello, mediana con recorte 20-80 % para ojos. La diferencia con la mediana es de 1-2 puntos en validación cruzada, dentro del ruido; ver la nota sobre A.7 en el informe del #68.
- **Equidad (proxy ITA, no Monk)**: exactitud en 4 estaciones entre 53 % y 64 % según la banda de ITA, sin una banda claramente peor. Las bandas oscuras tienen pocas imágenes (morena 112, oscura 28).
- **Estabilidad (proxy)**: la misma imagen conserva su estación en el 95-97 % de los casos con cambios de exposición, JPEG o escala, y solo en el 85-87 % con un cambio de balance de blancos. La normalización de luz (A.9) importa.
- El informe completo, la matriz de confusión y el artefacto están fuera del repositorio, junto al manifiesto del dataset.

### Clasificador de prendas `prendas-v1` (2026-10-27, issue #69)

Entrenado con `tools/entrenamiento/prendas/` (semilla 42, 15 épocas, la mejor es la 13). La prueba es val2020 de Fashionpedia (4.177 recortes) más el 10 % de personas de Grigorev (280), con todas las licencias: medir no mete esas imágenes en los pesos.

| Variante | Tipo (prueba) | Patrón (prueba) | Tamaño | Latencia en PC, 1 hilo |
|---|---|---|---|---|
| PyTorch FP32 | 76,9 % | 77,6 % | — | — |
| LiteRT FP32 | 76,9 % | 77,6 % | 6,0 MB | 1,9 ms |
| **LiteRT FP16 (elegida)** | **77,0 %** | **77,6 %** | **3,1 MB** | **1,8 ms** |
| LiteRT INT8 por canal (PTQ) | 47,8 % | 46,4 % | 1,8 MB | 3,0 ms |

- **Por qué FP16 y no INT8**: el criterio era perder como mucho 1 punto por cabeza, y la cuantización INT8 tras el entrenamiento perdió unos 30. MobileNetV3 cuantiza mal sin QAT (hard-swish y bloques SE). FP16 no pierde nada y cabe de sobra en el presupuesto de 15 MB.
- **Por fuente**: el tipo acierta el 90,0 % en las fotos de Grigorev, que son prendas sueltas como las de la app, y el 76,1 % en los recortes de Fashionpedia, que son prendas puestas.
- **Recall medio por clase**: 70,0 % en tipo y 46,5 % en patrón. La exactitud de patrón está inflada por LISO (86,6 % de recall, dos tercios de los casos); ANIMAL (21 %), GEOMETRICO (27 %), PUNTOS (29 %) y OTRO_ESTAMPADO (32 %) son débiles. En tipo, las clases flojas son las de menos datos de entrenamiento: CARDIGAN, CHALECO, SUETER y ENTERIZO, entre 25 % y 48 %, con 12 a 22 casos de prueba cada una.
- **Validación**: 82,8 % en tipo y 83,0 % en patrón, con las mismas licencias que el entrenamiento.
- Los pesos, los tres `.tflite`, el manifiesto con la licencia y el origen de cada recorte, y `evaluacion.json` están fuera del repositorio. Los SHA-256 de las fuentes descargadas están en `fuentes.json`.
