# Respuestas a las preguntas de implementación — WearHack

_2026-10-01 (actualizado con las decisiones del bloque G) · Fuente de verdad: stack-tecnologico, protocolos-puertos, guia-repositorio, politica-datos-colorimetria y MCP.md, más las fuentes externas citadas._

**Convención**
- **Definido**: decidido y documentado. Usar tal cual.
- **No definido**: no se decidió. No inventar el valor. Dejarlo como parámetro en `configuracion` (o constante con TODO) y avisar.
- **Propuesta**: sugerencia, **todavía no decidida por Ivan**. No implementar como definitiva hasta que la confirme.

## Correcciones previas importantes

1. **SmartPersonalColor es más débil de lo que dicen los documentos.** La publicación oficial (MIT App Inventor Community, "[F/OS] Smart Personal Color", feb. 2026) solo publica:
   - Una tabla de **8 combinaciones** binarias, no 12.
   - Sin cortes numéricos.
   - En **HSV** (no Lab), sobre el color **promedio** de piel.
   - Usa `android.media.FaceDetector`.
   
   Dos filas de su tabla contradicen la teoría estándar de 12 estaciones: "Bright Spring = Cool" y "Soft Summer = Deep". Un usuario del foro reporta que el enlace al repositorio de GitHub no funciona; solo están los `.aix`/`.aia` compilados en el foro. **No sirve como base del clasificador**, solo como referencia conceptual de los tres ejes y de la semilla fija.
2. **El "4º eje Contraste señalado por el autor" es inexacto.** El autor lista como mejoras un mapeo multi-eje más refinado, el sistema de 16 estaciones Sci/ART y landmarks de ojos y labios, pero no el contraste. El documento de stack se corrige.
3. **PCCS no da valores de piel, cabello ni iris** (tienes razón). El plan de "bootstrap desde PCCS" no produce centroides. El bloqueante real es un **conjunto de calibración etiquetado por un experto**, que no existe todavía.
4. **Licencias de datasets de ropa**: la familia DeepFashion está restringida a **investigación académica, con uso comercial prohibido**, lo que choca con el camino comercial de WearHack. DeepFashion2 además **no trae textura ni patrón** (ver C.17).

---

## A. Colorimetría: algoritmo

**1. Cortes numéricos de SmartPersonalColor.** **No definido / no publicado.**
- Sus ejes: temperatura desde la clasificación de subtono (Golden, Rosy, Neutral, Peach, Olive), valor desde el brillo HSV y croma desde la saturación HSV del color promedio de piel.
- Los cortes no aparecen en la publicación. El código solo estaría en el `.aix` compilado (licencia MIT según el badge de la publicación), descompilable si hiciera falta.
- **Traducción a Lab: no definida.** Propuesta: no traducir sus cortes, sino definir los ejes directamente en LCh: valor ≈ L*, croma ≈ C*, temperatura ≈ ángulo de matiz h°.

**2. Mapeo de ejes a las 12 estaciones.**
- **Definido (2026-10-01): el MVP clasifica en 4 estaciones** (primavera, verano, otoño, invierno); las 12 vienen después. El modelo de datos guarda `estacion` (4) y `subtipo` (12, opcional) para pasar a 12 sin migrar.
- Nearest-centroid (ya decidido): los ejes son continuos y el mapeo queda implícito en los centroides; no hace falta árbol de decisión.
- Referencia estándar para la etapa de 12: una **característica dominante** (claro, profundo, brillante, suave, cálido, frío) × una **inclinación** (cálida o fría).
- SmartPersonalColor solo mapea 8 combinaciones y no sirve como mapeo.

**3. Eje Contraste.** Concepto **definido**: diferencia de valor entre piel y cabello u ojos. **Fórmula y corte: no definidos.** Propuesta: |ΔL*| entre la mediana de piel y la de cabello (u ojos si no hay cabello), como dimensión continua más del vector de distancia, sin corte binario.

**4. Centroides de referencia.** **No definido.** No existe fuente; requieren datos etiquetados por un experto. Plan decidido en B.13. Hasta la etapa 1 se usa una heurística provisional, configurable y marcada como experimental.

**5. Pesos y métrica de distancia.** **Parcial.**
- **Definido**: los ojos pesan menos que piel y cabello (señal secundaria). Si falta un eje, la distancia se proyecta solo sobre los ejes disponibles, sin imputar.
- **No definido**: pesos numéricos, métrica y normalización.
- **Referencia (propuesta, no decidida)**: la tesis de Dinh (Leiden, 2026) usa distancia euclidiana sobre variables Lab/HSV y derivadas (calidez b − a, diferencias de L entre regiones, croma, a/L y b/L), elegidas por búsqueda voraz con validación cruzada, en un esquema jerárquico: subtono → contraste → estación → subtipo. Ver `investigacion-fuentes-colorimetria.md`, sección 3.

**6. Confianza y umbral de baja confianza.** **No definido.** Propuesta (Dinh 2026): probabilidades por inverso de la distancia, normalizadas; decidir con asignación dura y mostrar estación principal y segunda opción. Umbral de baja confianza: no definido.

**7. Percentiles del recorte.** **No definido.**
- Definido: recorte por percentil (no umbral fijo) más mediana de Lab; el de ojos es más agresivo.
- El "10 % / 10 %" para piel que apareció en la discusión fue un ejemplo, no una decisión.

**8. Mínimo de píxeles por región y margen borde-landmark.** **No definido.** Definido que van en `configuracion`, no en el código.

**9. "Normalizar el color" en el cliente.** **Parcial (2026-10-01).**
- **Definido (nivel 0)**: gestión de color correcta (perfil ICC → RGB lineal → XYZ → Lab D65; correcciones solo en RGB lineal); si el cliente recorta y recodifica, convierte antes a sRGB o conserva el perfil ICC (los iPhone suelen capturar en Display P3); recorte en PNG o JPEG de alta calidad; controles de calidad (píxeles quemados o negros, desenfoque, tamaño del rostro) que sugieren repetir sin obligar; cámara propia de la app.
- **Descartado**: gray world sobre el recorte (un recorte dominado por piel sesga el subtono).
- **Por decidir con el protocolo**: la técnica de corrección del color de la luz (blanco del ojo, brillos especulares o modelo aprendido; pantalla como flash solo si ninguna alcanza). Ver `protocolo-normalizacion-colorimetria.md`.
- Umbrales de los controles de calidad y tamaño mínimo del rostro: se fijarán con los datos del protocolo.

**10. Semilla y algoritmo de muestreo.**
- **Definido**: semilla fija (práctica tomada de SmartPersonalColor, que usa `new Random(42)`); en rostro, recorte por percentil + mediana de Lab por región (sin k-means).
- **No definido**: el valor de la semilla en WearHack.
- Para prendas (on-device): k-means o moda sobre la máscara en Lab, **k no definido**.

## B. Colorimetría: datos y calibración

**11. Regla de recalibración de centroides.** **No definido**, salvo: job batch nocturno con umbral mínimo de datos nuevos. (El "≥ 10" del documento es del ajuste de preferencias, no de esta regla.)

**12. ¿Las correcciones guardan los ejes usados?** **Definido: sí.** Cada clasificación guarda qué ejes se usaron, para no mezclar correcciones de 2 ejes con las de 3 al recalibrar. La corrección debe incluirlos.

**13. Datos de calibración inicial.** **Definido (2026-10-01): Deep Armocromia** como fuente de etiquetas. Experto colaborador y voluntarios: **descartados**.
- Dataset: 4.920 rostros etiquetados en 4 estaciones y 12 subtipos, por anotadores supervisados por expertos (4.000 entrenamiento / 920 prueba). Se pide a los autores para uso académico.
- **Licencia**: entrenamiento derivado de CelebA (solo investigación no comercial, sin explotación comercial de datos derivados). Los centroides sirven para la fase académica, no para el producto comercial.
- **Etapa 0**: estabilidad por persona con los integrantes y con MST-E (sin etiquetas de estación).
- **Etapa 1**: 4 estaciones (unas 25 etiquetas por clase bastan según Dinh 2026). Control de cordura: acercarse a las líneas base publicadas (~50-55 %).
- **Etapa 2**: 12 subtipos (unas 40 por clase); techo publicado ~31 %.
- Detalle de fuentes, cifras y pipeline de ingesta: `investigacion-fuentes-colorimetria.md`.

**14. Desvinculación de las correcciones.** **No definido.** Propuesta:
- Quien desvincula es el dueño de la colección (módulo Usuarios del Core), no el job.
- El job escribe en su propia colección hasta qué corrida o marca de tiempo consumió.
- Una tarea programada del Core desvincula las correcciones anteriores a esa marca.

## C. Prendas (on-device)

**15. Categorías de color de prenda.** **No definido**: ni la lista ni los Lab.
- Definido el mecanismo: Lab como fuente de verdad; categoría derivada por vecino más cercano contra centroides, **nunca como texto libre del cliente**, así que la derivación es del lado servidor; recalibración nocturna con `correcciones_clasificacion`.
- Dueño: módulo Clóset (ver G.41).

**16. Umbral de baja confianza del clasificador de prenda.** **No definido.**

**17. Datasets del clasificador.** **No decidido** (el documento dice "DeepFashion2 o Fashionpedia").
- **DeepFashion2** etiqueta categoría (13), estilo, escala, oclusión, zoom, punto de vista, caja, landmarks y máscara. **No trae textura ni patrón.** La familia DeepFashion es de uso académico (sin uso comercial); verificar los términos exactos de DeepFashion2 en su repositorio (github.com/switchablenorms/DeepFashion2).
- **Fashionpedia** (paper arXiv 2004.12276): atributos finos anotados por expertos, que incluyen la supercategoría "textile pattern"; imágenes de Flickr y sitios de licencia libre. **Textura o material: por verificar. Licencia: por verificar.**
- Conclusión: hoy no hay fuente confirmada para las etiquetas de textura.

**18. Valores de los enums.** **Parcial.**
- **Definido**:
  - `slot_outfit`, con cardinalidades: TORSO_SUPERIOR, TORSO_INFERIOR, CUERPO_COMPLETO (excluyente con los dos anteriores), CALZADO, EXTERIOR, ACCESORIO_CUELLO, ACCESORIO_RELOJ, ACCESORIO_CINTURA, ACCESORIO_CABEZA, ACCESORIO_BOLSO y ACCESORIO_OJOS, todos con cardinalidad 1. ACCESORIO_JOYERIA admite varios, con tope configurable (por defecto 3).
  - **Formalidad** ordinal: deportivo, casual, smart casual, formal.
  - **Patrón**: al menos la distinción liso / no liso, por la regla de máximo 1 prenda no lisa.
- **No definido**: valores de tipo, textura, patrón (más allá de liso) y `clima_apto`.
- **Tabla (tipo, textura) → clima_apto**: definido que es estática en código; **su contenido no está escrito**.

**19. Checkpoint de u2netp ajustado a ropa.** **No encontrado ni decidido.** Candidato a evaluar, no confirmado: el modelo `u2net_cloth_seg` de rembg (origen: levindabhi/cloth-segmentation). Pero es el U²-Net completo (no la variante p), está entrenado con ropa puesta en personas (no prendas sobre una superficie) y su licencia está por verificar.

**20. Dispositivo de referencia de gama media-baja.** **No definido**: RAM, CPU, Android e iOS mínimos, latencia por imagen y RAM pico. Verificar además los mínimos que imponen Flutter, ML Kit y el plugin de TFLite.

**21. Pérdida tolerable al cuantizar a INT8.** **No definido.**

## D. Recomendación

**22. Fórmula del score.** **No definido** (componentes, pesos y combinación). Lo definido:
- Compatibilidad de color por ángulo de matiz en LCh (análogos, complementarios, triádicos; neutros con C* bajo combinan con todo).
- Formalidad ordinal.
- Patrón como regla dura (máximo 1 no liso).
- Textura aprendida por coocurrencia.
- Mood y estación como pesos suaves.
- Vector de pesos personal (color y formalidad).

**23. Tolerancias de matiz y umbral de C\* neutro.** **No definido.** Referencia no decidida: SmartPersonalColor genera paletas con análogos a ±30° y ±60°, complementario a 180° y triádico a 120°.

**24. Mapeo evento → rango de formalidad.** **No definido.** Definido que vive en `configuracion` y que es filtro duro.

**25. Valores de los pesos suaves de mood y estación.** **No definido.** Definido: la estación solo se ajusta si |latitud| > 23.5°.

**26. Aprendizaje por selección.** **Parcial.**
- **Definido**: se compara el outfit elegido con los descartados del mismo lote; se ajustan el vector de pesos personal y una tabla de coocurrencia de pares de textura (positiva y negativa); job nocturno solo para usuarios con ≥ 10 selecciones nuevas.
- **No definido**: fórmula de actualización y tasa de aprendizaje.

**27. N de "elegir el mejor de N".** **No definido.**

**28. Prenda puente.** **Parcial.**
- **Definido**: se cuentan directamente las combinaciones válidas de la prenda en su slot con las prendas existentes en los slots principales (torso superior, torso inferior o cuerpo completo, calzado, exterior; accesorios y joyería no cuentan). El cálculo es híbrido: batch nocturno más tiempo real con la misma función.
- **No definido**: umbral mínimo y desempate. (El "12" del pitch es un ejemplo.)

## E. Metas y medición

**29. RNF07 (≥ 85 %).** **No definido** sobre qué modelo ni con qué conjunto; confirmar en el documento de requisitos original (el "en detección/colorimetría" de protocolos fue una interpretación).
- **Dato importante**: con la evidencia publicada, un 85 % de acuerdo con etiquetas expertas **no es alcanzable** en colorimetría. El mejor resultado sobre Deep Armocromia es 55,4 % en 4 estaciones y 31,8 % en 12; por capa, subtono ~70 % y contraste ~76 %.
- **Propuesta (no decidida)**: exactitud por capa, top-2 en 4 estaciones, estabilidad por persona, equidad por tono de piel (escala Monk) y comparación con las líneas base publicadas.
- Aparte, `Criterios_de_Calidad` pide ≥ 90 % de recomendaciones que cumplan los parámetros: es otra métrica.

**30. Latencias de IA.** **Definido** en protocolos, sección 9: objetivo ≤ 5 s (RNF01) y techo de ~10 s (timeout, alineado con el criterio de calidad de generación de outfit). Aplica a outfit y a colorimetría. Consulta del clóset: ≤ 2 s (`Criterios_de_Calidad`).

**31. Latencia de digitalizar una prenda.** **No definido.** (El "~30 ms por imagen" de u2netp en el stack es una referencia de CPU, no una meta en móvil.)

## F. Datos y política para entrenar

**32. Dataset de calibración con fotos de integrantes.** **Definido (2026-10-01): sí**, solo integrantes y solo para medir estabilidad, con consentimiento escrito **específico para calibración**. Se guardan imágenes capturadas con la app, metadatos de captura y valores derivados; cifrado en una bóveda Cryptomator sobre una carpeta institucional de la universidad, fuera del repositorio, con acceso limitado a personas nombradas y borrable a petición. **El código nunca debe leer ni escribir fotos de calibración dentro del repositorio.** Celular reservado para la validación final: Android de gama media. Detalle en la política (sección 12) y en el protocolo de normalización.

**33. Datasets públicos de rostros.** **Definido (2026-10-01).**
- **Deep Armocromia**: para centroides y evaluación, solo en la fase académica (licencia de investigación; derivado de CelebA).
- **MST-E** (Google) y **Casual Conversations v2** (Meta): solo para evaluar robustez y equidad, sin entrenar centroides; sus términos están por leer.
- **CelebAMask-HQ**: opcional, para validar la segmentación (solo investigación no comercial).
- **Descartados**: Roboflow "Color Analysis" (71 imágenes) y Colorinsight (sin repositorio ni licencia localizados).
- **No usar** modelos de visión-lenguaje como anotadores.

**34. Cuántos aportan fotos y qué diversidad.** Los integrantes, solo para estabilidad. La diversidad de tonos se evalúa con MST-E (10 tonos de la escala Monk) y Casual Conversations v2 (incluye México y Brasil), no con el equipo. No se reclutan voluntarios externos.

**35. Comité de ética.** **No se sabe.** Como ya no se reclutan voluntarios externos, la consulta solo es necesaria si el trabajo académico lo exige para las pruebas con los propios integrantes. Conviene preguntarlo de todos modos.

## G. Contradicciones entre documentos y código

**36. Puerto del Core.** **Definido (2026-10-01): 8090**, como el repositorio. Los documentos ya están actualizados.

**37. Jobs batch.** **Definido: valen los documentos.** Sin endpoints HTTP. Cada job es un comando de la imagen (`python -m jobs.<nombre>`):
- En el lab: `docker compose run`, a mano o por cron al inicio de la ventana de prueba.
- En el objetivo: EventBridge Scheduler → ECS RunTask.
- El prompt que pedía endpoints más un scheduler en compose queda descartado.

**38. Centroides en la llamada síncrona.**
- **Definido (2026-09-28, sustituye al "sin estado respecto a Mongo" de la versión anterior de protocolos)**: los servicios de IA leen **solo sus propias colecciones**; nunca las del Core.
- **No definido** cómo. Propuesta:
  - Colorimetría carga los centroides al arrancar y los recarga cuando cambia su versión (los recalibra el job nocturno), sin leer Mongo en cada petición.
  - Recomendación lee los pesos del usuario de su propia colección por `usuario_id`, con caché opcional.

**39. Rutas de IA y `usuario_id`.** **Definido**: `POST /v1/colorimetria/analizar` y `POST /v1/recomendacion/generar`. El DTO de recomendación **sí lleva `usuario_id`** como dato de negocio, no como credencial; el motor lo necesita para leer los pesos del usuario.

**40. Estructura.** **Definido (2026-10-01): la del repositorio**: `client/` en la raíz y paquete raíz `com.wearhack`, con un subpaquete por módulo (`usuarios`, `closet`, `outfits`, `publicidad`). La clase `@SpringBootApplication` va en `com.wearhack`. Spring Modulith trata como módulo cada subpaquete directo, así que un paquete compartido (configuración técnica, utilidades) se declara explícitamente como módulo compartido para que la verificación de fronteras no falle.

**41. Dueños.** **Definido (2026-10-01).**
- **Centroides de color de prenda**: dueño el **módulo Clóset**. Solo Clóset los usa (asigna la categoría al guardar la prenda; el Motor de Recomendación trabaja con Lab y ángulo de matiz, no con la categoría). La recalibración es una **tarea programada de Spring dentro del Core** (promedio de correcciones por categoría, con umbral mínimo de datos nuevos), no un job de Python. En la arquitectura objetivo, con varias réplicas, necesita un bloqueo para correr una sola vez (por ejemplo ShedLock); en el host único del lab no aplica. Lista de categorías, valores Lab y umbrales: siguen sin definir (C.15).
- **`configuracion`**: una colección con **un documento por dueño**: `outfits` (dress codes, topes de slots), `colorimetria` (píxeles mínimos, margen, percentiles), `closet` (umbral de baja confianza), `recomendacion` (umbral de selecciones, pesos iniciales). Cada componente lee y escribe solo su documento. Los valores siguen sin definir.

**42. Caddy y TLS en el MVP del lab.** **Definido: dentro del alcance** (topología del lab, 2026-09-28). La verificación del certificado está pendiente. Es **requisito previo** para cualquier prueba con rostros reales: la política exige TLS para el recorte.

---

## Resumen para priorizar

- **Bloqueantes de colorimetría**: acceso a Deep Armocromia (B.13); decidir las propuestas de clasificador, métricas y presentación (A.5, A.6, E.29); normalización en el cliente (A.9).
- **Bloqueantes de prendas**: valores de los enums y tabla de clima (C.18); fuente de etiquetas de textura (C.17).
- **Parametrizables sin bloquear**: todo lo de D y los umbrales de A y C, como valores en `configuracion` con marcadores, pendientes de decisión.
- **Decisiones rápidas**: G.36, G.40 y G.41 ya cerradas (2026-10-01).
