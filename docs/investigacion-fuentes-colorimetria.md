# Investigación: fuentes de datos para calibrar la colorimetría — WearHack

_2026-10-01 · Decisión de partida: descartadas las fuentes A (experto colaborador) y B (voluntarios con análisis previo); se trabaja con la fuente C (Deep Armocromia) y se buscan todas las fuentes e ingestas complementarias._

## 1. Resumen

1. **Hay una sola fuente etiquetada útil: Deep Armocromia** (Stacchio, Paolanti, Spigarelli, Frontoni; ECCV Workshops 2024). Según la tesis de Leiden que lo reutilizó, tiene **4.920 rostros etiquetados** en 4 estaciones y 12 subtipos, por anotadores supervisados por expertos, separados en 4.000 de entrenamiento y 920 de prueba. Es el único dataset etiquetado de color personal que se presenta como disponible públicamente para investigación.
2. **El techo realista es bajo**, y hay que asumirlo desde ya. El mejor resultado publicado sobre ese dataset es el de una CNN, que acierta con la etiqueta experta un **55,4 % en 4 estaciones** y un **31,8 % en 12 subtipos**. Un nearest centroid jerárquico, interpretable, logra 53,97 % y 30,84 %. Por capas: subtono cálido o frío ~70 %, contraste alto o bajo ~76 %. El azar sería 25 % y 8,3 %. La causa no es el modelo: la tarea es subjetiva y las clases se solapan incluso para expertos.
3. **Licencia: sirve para la fase académica, no para el producto comercial.** El entrenamiento de Deep Armocromia sale de CelebA, que es solo para investigación no comercial y prohíbe explotar comercialmente las imágenes y **los datos derivados**. Unos centroides calculados con esos datos son, razonablemente, datos derivados (por validar con un abogado). Antes de lanzar comercialmente habrá que recalcularlos con datos de derechos compatibles.
4. **Sesgo poblacional**: son celebridades, de medios occidentales, mayoritariamente de piel clara. La población colombiana queda mal representada. Hay que medir la robustez por tono de piel con datasets consentidos y diversos (MST-E, Casual Conversations v2) y con el equipo.

## 2. Fuentes evaluadas

| Fuente | Qué aporta | Etiquetas | Tamaño | Licencia y acceso | Uso en WearHack |
|---|---|---|---|---|---|
| **Deep Armocromia** | Etiquetas de estación y subtipo | 4 estaciones + 12 subtipos | 4.920 (4.000 entrenamiento / 920 prueba) | Investigación. Pedirlo a los autores (U. de Macerata y U. de Bologna). Ese grupo distribuye otros datasets con formulario firmado desde un correo institucional; para este no está confirmado | Centroides iniciales (fase académica) y benchmark contra las líneas base publicadas |
| **Tesis de Dinh** (Leiden, jul. 2026), "Teaching Machines to See Seasonal Color" | Metodología, parámetros y líneas base sobre Deep Armocromia | — | — | Tesis pública: theses.liacs.nl/3755 | Referencia para los valores por defecto del clasificador (sección 3) |
| **MST-E** (Google) | Robustez del muestreo de piel por tono y por luz | Escala Monk de 10 tonos | 19 personas, 1.515 imágenes y 31 videos; varias condiciones de luz; fotos de stock con modelos (TONL) | Términos de uso publicados en skintone.google: **por leer** | Etapa 0: estabilidad por persona y por tono de piel |
| **Casual Conversations v2** (Meta) | Equidad por tono de piel, incluida Latinoamérica | Fitzpatrick y Monk (anotadas); edad y género declarados | 5.567 participantes pagados y con consentimiento, 26.467 videos; Brasil, India, Indonesia, México, Vietnam, Filipinas, EE. UU. | Acuerdo de licencia: pensado para **evaluar** modelos ya entrenados; solo permite entrenar con ciertas etiquetas | Evaluar la equidad de la segmentación y de la extracción de color; no para entrenar centroides |
| **CelebAMask-HQ** | Máscaras de piel, cabello y ojos | Segmentación | ~30.000 | Solo investigación no comercial (familia CelebA) | Validar la segmentación de MediaPipe contra máscaras de referencia |
| Colorinsight (2023) | Referencia histórica | 4 estaciones, parcial | Celebridades coreanas | Repositorio y licencia no localizados | Descartado: 20-30 % con clasificadores clásicos |
| Roboflow "Color Analysis" | — | 5 clases ("Fall" y "Autumn" duplicadas) | 71 imágenes | CC BY 4.0 declarada | Descartado: tamaño y calidad; su propio modelo reporta 23,3 % |
| AI Hub (Corea) | — | — | — | No se encontró un dataset de color personal | — |
| Modelos de visión-lenguaje como anotadores (Gemini, Claude, etc.) | — | — | — | — | **No recomendado**: no es reproducible ni auditable (la tesis lo excluye por eso), y enviar rostros a un tercero choca con la política de datos |
| Correcciones de usuarios (producto) | Etiquetas débiles con el tiempo | — | — | Propio | Recalibración posterior (ya diseñado); ruidoso |

## 3. Implicaciones de diseño — propuestas, no decididas

Todas salen de la tesis de Dinh, medidas sobre Deep Armocromia.

**a. Clasificador jerárquico con nearest centroid.** En la tesis, nearest centroid superó a K-Means en todas las pruebas; Lab y HSV superaron con claridad a RGB; y el enfoque jerárquico superó al plano.
- **Capa 1, subtono**: cálido o frío.
- **Capa 2, contraste**: alto o bajo. Las dos capas juntas dan las 4 estaciones: primavera (cálido, bajo), verano (frío, bajo), otoño (cálido, alto), invierno (frío, alto).
- **Capa 3, vivacidad**: dentro de cada estación, el subtipo (para la etapa de 12).
- **Distancia**: euclidiana.
- **Decisión**: asignación dura. **Confianza**: probabilidades por inverso de la distancia, normalizadas, para mostrar la segunda opción. En la tesis, la asignación dura fue igual o mejor que la suave para decidir.

**b. Variables.** La media por región (piel, cabello, ojos) en Lab y HSV, más variables derivadas:
- Calidez: b − a por región.
- Diferencias de luminosidad entre regiones, y el rango total de L.
- Croma por región, y la razón entre croma de cabello y de piel.
- a/L y b/L, para reducir la sensibilidad a la iluminación.

La tesis eligió los subconjuntos por búsqueda voraz con validación cruzada. Diferencia con nuestro diseño: ella usa la **media** y nosotros recorte por percentil y **mediana**. Es una diferencia a medir, no a resolver por intuición.

**c. Datos necesarios.** La exactitud se estabiliza con unas **25 etiquetas por clase** en 4 estaciones (~100 en total) y unas **40 por clase** en 12 subtipos (~500). Deep Armocromia alcanza de sobra.

**d. Presentar el resultado con incertidumbre.** Mostrar estación principal, segunda opción y una explicación (más cálido, más contraste...). La tesis lo justifica por la subjetividad de la tarea y por la confianza del usuario. Las confusiones más frecuentes son entre estaciones vecinas: otoño con invierno, primavera con verano.

**e. El Motor de Recomendación no necesita la etiqueta.** Podría usar las puntuaciones continuas de subtono, contraste y vivacidad, que son más fiables (~70-76 % por capa) que la estación (~54 %).

**f. Métricas en lugar de "≥ 85 %" para colorimetría.** Con la evidencia disponible, un 85 % de acierto contra etiquetas expertas no es alcanzable ni para 4 estaciones. Propuesta:
- Exactitud por capa (subtono, contraste).
- Top-2 en 4 estaciones.
- Estabilidad por persona.
- Equidad por tono de piel (escala Monk).
- Comparación con las líneas base publicadas.

Confirmar antes qué dice exactamente RNF07 en el documento de requisitos.

## 4. Ingesta propuesta (pipeline)

1. Solicitar Deep Armocromia a los autores desde el correo institucional de la universidad, para uso académico.
2. Pasar sus imágenes por **nuestro** pipeline (segmentación de MediaPipe + muestreo) y extraer las variables.
3. Calcular centroides con su conjunto de entrenamiento y evaluar en su conjunto de prueba.
4. **Control de cordura**: una exactitud cercana a las líneas base (~50 % en 4 estaciones) indica que nuestro pipeline funciona. Muy por debajo indica un problema de segmentación o muestreo.
5. Medir la robustez con MST-E (luces y tonos) y la equidad con Casual Conversations v2, sin usarlos para entrenar centroides.
6. Estabilidad con el equipo: varias fotos por persona con luces distintas, con el consentimiento específico de calibración.

Almacenamiento de todo lo anterior: según la política de datos, sección 12 (fuera del repositorio, cifrado, acceso limitado).

## 5. Riesgos

- **Comercial**: los centroides derivados de Deep Armocromia (vía CelebA) no deberían llegar al producto comercial. Hará falta otra fuente con derechos compatibles; probablemente reaparezca la necesidad de un experto en esa etapa.
- **Dominio**: celebridades fotografiadas profesionalmente (y a menudo maquilladas) frente a selfies con cámaras de celular. Hay que esperar una caída de exactitud en uso real.
- **Población**: subrepresentación de pieles medias y oscuras. Se mide con MST-E y Casual Conversations v2.
- **Taxonomía**: Deep Armocromia sigue Armocromia, de tradición italiana. Sus 12 subtipos coinciden en nombres con el sistema estándar, pero conviene verificar las definiciones del protocolo de anotación del paper.

## 6. Pendientes

- Solicitud a los autores de Deep Armocromia (redactar el correo).
- Leer los términos de uso de MST-E y el acuerdo de Casual Conversations v2.
- Decidir las propuestas de la sección 3.
- Validación legal de la lectura de CelebA ("datos derivados").
