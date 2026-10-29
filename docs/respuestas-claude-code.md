# Respuestas a las preguntas de implementación — WearHack

_2026-10-01 (actualizado con las decisiones del bloque G) · Fuente de verdad: stack-tecnologico, protocolos-puertos, guia-repositorio, politica-datos-colorimetria y MCP.md, más las fuentes externas citadas._

> **Estrategia (2026-10-01): el MVP es exclusivamente académico.** Se pueden usar datasets con licencia de investigación, respetando cada licencia por separado, y todo artefacto entrenado o calibrado con ellos se anota en `procedencia-datos-wearhack.md`. Detalle en el stack, sección 6.

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

**1. Cortes numéricos de SmartPersonalColor.** **Ya no aplica (2026-10-01).** SmartPersonalColor solo es referencia conceptual; el clasificador es el jerárquico con nearest centroid (A.2, A.5).

**2. Mapeo de ejes a las estaciones.** **Definido (2026-10-01).**
- El MVP clasifica en **4 estaciones**; las 12 vienen después. El modelo de datos guarda `estacion` (4) y `subtipo` (12, opcional).
- **Clasificador jerárquico** (tesis de Dinh, Leiden, 2026): capa 1 subtono (cálido o frío); capa 2 contraste (alto o bajo). Las dos dan la estación: primavera (cálido, bajo), verano (frío, bajo), otoño (cálido, alto), invierno (frío, alto). Capa 3, vivacidad, para el subtipo en la etapa de 12.
- Centroides calculados con Deep Armocromia (pendiente de acceso). Mientras no lleguen, heurística provisional configurable y marcada como experimental.
- SmartPersonalColor no se usa como mapeo.

**3. Eje Contraste.** **Definido (2026-10-01).** Es una variable continua, sin corte binario propio: las diferencias de L* entre piel y cabello (o piel y ojos si no hay cabello) entran como variables del clasificador jerárquico (A.5). La capa de contraste alto o bajo sale de los centroides, no de un umbral fijo.

**4. Centroides de referencia.** **No definido.** No existe fuente; requieren datos etiquetados por un experto. Plan decidido en B.13. Hasta la etapa 1 se usa una heurística provisional, configurable y marcada como experimental.

**5. Pesos y métrica de distancia.** **Definido el punto de partida (2026-10-01).**
- Distancia euclidiana sobre variables Lab/HSV por región y derivadas: calidez b − a, diferencias de L entre regiones, croma y a/L y b/L. El subconjunto se elige por búsqueda voraz con validación cruzada en el conjunto de entrenamiento de Deep Armocromia, como en la tesis.
- Si falta un eje, la distancia se proyecta solo sobre los ejes disponibles, sin imputar. Los ojos son señal secundaria.
- Diferencia con la tesis a medir: ella usa la media por región y nosotros recorte por percentil y mediana.

**6. Confianza y umbral de baja confianza.** **Parcial (2026-10-01).** Definido: decisión dura para la estación; confianza por inverso de la distancia, normalizada; la app muestra la estación principal, una segunda opción y una explicación breve. **Umbral de baja confianza: no definido.**

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

**11. Reglas de recalibración.** **Definido (2026-10-01).**
- **Centroides de estación (colorimetría; job nocturno de la imagen de Colorimetría)**:
  - Mezcla con lo anterior: `nuevo = (n0·actual + Σ correcciones) / (n0 + n)`, con `n0 = 25` (configurable).
  - Mínimo para actuar: **20 correcciones nuevas** en esa estación desde la última recalibración.
  - Tope de movimiento por corrida (valor configurable, por definir con datos).
  - **Sin retroceso**: antes de publicar, se evalúa contra un conjunto fijo (el de prueba de Deep Armocromia en la fase académica, más las métricas de estabilidad). Si alguna métrica empeora más de 1 punto porcentual, se descarta y se mantiene la versión anterior.
  - **Versionado**: cada versión de centroides se guarda y se puede revertir. Colorimetría recarga los centroides cuando cambia la versión (G.38).
  - **Por ejes**: una corrección hecha sin cabello visible solo mueve las dimensiones medidas.
- **Color de prenda (módulo Clóset; tarea programada del Core)**: los centroides ISCC-NBS **no se mueven** (son un estándar). Se ajusta la **tabla de traducción** bloque → categoría: si un bloque acumula **≥ 10 correcciones** y **≥ 70 %** coincide en una categoría distinta a la de la tabla, se cambia la traducción de ese bloque y el cambio queda registrado para revisión.

**12. ¿Las correcciones guardan los ejes usados?** **Definido: sí.** Cada clasificación guarda qué ejes se usaron, para no mezclar correcciones de 2 ejes con las de 3 al recalibrar. La corrección debe incluirlos.

**13. Datos de calibración inicial.** **Definido (2026-10-01): Deep Armocromia** como fuente de etiquetas. Experto colaborador y voluntarios: **descartados**.
- Dataset: 4.920 rostros etiquetados en 4 estaciones y 12 subtipos, por anotadores supervisados por expertos (4.000 entrenamiento / 920 prueba). Se pide a los autores para uso académico.
- **Licencia**: entrenamiento derivado de CelebA (solo investigación no comercial, sin explotación comercial de datos derivados). Los centroides sirven para la fase académica, no para el producto comercial.
- **Etapa 0**: estabilidad por persona con los integrantes y con MST-E (sin etiquetas de estación).
- **Etapa 1**: 4 estaciones (unas 25 etiquetas por clase bastan según Dinh 2026). Control de cordura: acercarse a las líneas base publicadas (~50-55 %).
- **Etapa 2**: 12 subtipos (unas 40 por clase); techo publicado ~31 %.
- Detalle de fuentes, cifras y pipeline de ingesta: `investigacion-fuentes-colorimetria.md`.

**14. Desvinculación de las correcciones.** **Definido (2026-10-01); pendiente de validación legal.**
- **Marca del job**: al terminar cada corrida, el job de recalibración escribe en su propia colección (`recalibraciones`: corrida, versión de centroides publicada o descartada, hasta qué corrección consumió).
- **Desvinculación en el Core**: una tarea programada del módulo Usuarios (dueño de las correcciones de colorimetría) lee esa marca con un contrato de solo lectura y, en las correcciones consumidas, **elimina el `usuario_id`** y **reduce la fecha a mes y año**.
- **Plazo máximo**: ninguna corrección permanece vinculada más de **30 días**, aunque no se haya consumido.
- **Revocación**: si el usuario revoca su consentimiento antes de la desvinculación, sus correcciones se **borran**. Después ya no se le pueden atribuir y quedan como datos agregados.
- **Correcciones de color de prenda**: mismo trato por minimización. Las procesa el propio Core y las desvincula al usarlas.

## C. Prendas (on-device)

**15. Categorías de color de prenda.** **Definido (2026-10-01).**
- **Método**: el color Lab de la prenda se asigna al **bloque más cercano entre los 267 bloques del nivel 3 de ISCC-NBS**, medido con **ΔE00**. Luego una **tabla fija de traducción** pasa cada bloque a una de las 20 categorías. Claude Code genera esa tabla con reglas a partir del nombre del bloque (tono + modificador: claro, oscuro, pálido, intenso...) y el equipo la revisa una vez.
- **Centroides**: de la publicación del NBS de 1958 (Journal of Research of the NBS, nvlpubs.nist.gov), en notación Munsell, convertidos a Lab D65 con `colour-science` (BSD). **No** usar el paquete de R `munsellinterpol` (GPL).
- **Las 20 categorías**:
  - `NEGRO`: negro y casi negros.
  - `BLANCO`: blanco, crema, hueso.
  - `GRIS`: grises, incluidos los de croma muy bajo con tinte.
  - `BEIGE`: beige, arena, camel claro, caqui claro.
  - `CAFE`: marrón, camel oscuro, chocolate.
  - `VINOTINTO`: burdeos, vino (rojos y rojos purpúreos oscuros o profundos).
  - `ROJO`: rojos intensos o moderados.
  - `ROSADO`: rosa, rosa palo, salmón claro.
  - `FUCSIA`: fucsia, magenta.
  - `NARANJA`: naranja, coral.
  - `AMARILLO`: amarillos claros e intensos.
  - `MOSTAZA`: amarillos oscuros, apagados o anaranjados.
  - `VERDE_OLIVA`: oliva, militar, caqui oscuro.
  - `VERDE`: verde, verde amarillento.
  - `TURQUESA`: turquesa, aguamarina.
  - `CELESTE`: azules claros, muy claros o pálidos.
  - `AZUL`: azules moderados o intensos.
  - `AZUL_MARINO`: azules oscuros, muy oscuros o profundos.
  - `MORADO`: púrpura, violeta, púrpura rojizo de medio a oscuro.
  - `LILA`: púrpuras y violetas claros o pálidos.
- La categoría solo sirve para mostrar y filtrar en la interfaz; armonía y paleta se calculan con el Lab. El denim queda en `AZUL` o `AZUL_MARINO` según su tono; su condición de neutro la marca la textura.
- **Mecanismo** (ya definido): Lab como fuente de verdad; cálculo en el servidor por el módulo Clóset; recalibración con `correcciones_clasificacion` (si un usuario corrige la categoría, se registra el Lab con la categoría confirmada).

**16. Umbral de baja confianza del clasificador de prenda.** **No definido.**

**17. Datasets del clasificador de prendas.** **Definido (2026-10-01).**
- **Fashionpedia** (base): 27 categorías y 294 atributos (incluido el patrón textil), con máscaras. Verificado en su sitio oficial: anotaciones, ontología y sitio CC BY 4.0; las imágenes se rigen por los términos de Flickr, Unsplash, Burst, Freestocks, Kaboompics y Pexels. Revisar si los de Unsplash y Pexels dicen algo sobre entrenar modelos.
- **Clothing dataset** (Alexey Grigorev): más de 5.000 imágenes, 20 clases, uso libre incluido el comercial; son prendas fotografiadas sueltas, el dominio de la app.
- **Open Images V7**: solo para las clases que falten (calzado, accesorios). Anotaciones CC BY 4.0, imágenes CC BY 2.0 sin garantía por imagen. Descargar solo esas clases. **No usar el ecosistema YOLO de Ultralytics** (AGPL-3.0).
- **DeepFashion2: retirado** (acuerdo firmado, pero no se usa).
- **Clasificador del MVP: dos cabezas, tipo y patrón.** Sin cabeza de textura (ver C.18). Con estas fuentes, el clasificador es usable comercialmente con atribución.

**18. Valores de los enums.** **Definido (2026-10-01).**
- **`slot_outfit`** (ya definido): TORSO_SUPERIOR, TORSO_INFERIOR, CUERPO_COMPLETO (excluyente con los dos anteriores), CALZADO, EXTERIOR, ACCESORIO_CUELLO, ACCESORIO_RELOJ, ACCESORIO_CINTURA, ACCESORIO_CABEZA, ACCESORIO_BOLSO y ACCESORIO_OJOS, todos con cardinalidad 1; ACCESORIO_JOYERIA admite varios, con tope configurable (por defecto 3).
- **`tipo`** (definido), con su slot por defecto (editable) y su origen:
  - TORSO_SUPERIOR: `CAMISA` (camisa o blusa), `CAMISETA` (camiseta, top, buzo), `SUETER`. Clasificador.
  - EXTERIOR: `CARDIGAN`, `CHAQUETA`, `ABRIGO` (incluye capa), `CHALECO`. Clasificador.
  - TORSO_INFERIOR: `PANTALON`, `SHORT`, `FALDA`. Clasificador.
  - CUERPO_COMPLETO: `VESTIDO`, `ENTERIZO`. Clasificador.
  - CALZADO: `CALZADO`, con `subtipo_calzado` manual opcional: `TENIS`, `ZAPATO_FORMAL`, `BOTAS`, `SANDALIAS`, `TACONES`. Tipo por clasificador; subtipo manual.
  - Accesorios: `GAFAS` (OJOS), `SOMBRERO` y `ACCESORIO_CABELLO` (CABEZA), `CORBATA` y `BUFANDA` (CUELLO), `RELOJ` (RELOJ), `CINTURON` (CINTURA), `BOLSO` (BOLSO). Clasificador.
  - `JOYERIA` (JOYERIA): **manual**, porque Fashionpedia no tiene esa categoría.
  - Fuera del MVP: guantes, medias, calentadores y paraguas.
  - Nota: Fashionpedia no distingue blazer de chaqueta casual; esa diferencia la da la formalidad, no el tipo.
- **`patron`** (definido): `LISO`, `RAYAS`, `CUADROS`, `PUNTOS`, `FLORAL`, `ANIMAL`, `GEOMETRICO`, `OTRO_ESTAMPADO` (letras, logos, abstracto). La regla del motor solo usa liso o no liso. Se mapea desde los atributos de patrón textil de Fashionpedia; la lista exacta se confirma al descargarlo.
- **`textura`** (definido 2026-10-01): **sin clasificador en el MVP**; familias visibles, no fibras. Cada corrección se guarda, con consentimiento, como dato para entrenar una cabeza de textura más adelante.
  - Valores: `LISO_LIGERO` (tejidos lisos y livianos), `DENIM`, `PUNTO` (tejido de punto visible), `PANO` (sastrería, lana peinada), `CUERO` (incluido el sintético), `SATIN` (satín y seda), `LINO`, `DEPORTIVO` (sintéticos técnicos), `ACOLCHADO` (acolchado, plumón, borrego, fleece), `OTRA`.
  - Calzado y accesorios: **sin textura** (`null`); su clima sale del tipo y del subtipo.
  - **Por defecto, sin preguntar**: CAMISETA, CAMISA, ENTERIZO y SHORT → `LISO_LIGERO`; SUETER y CARDIGAN → `PUNTO`; ABRIGO → `PANO`.
  - **Se pregunta en la pantalla de revisión al final de la sesión de captura**, nunca durante la captura (ver E.31; la primera opción va preseleccionada): PANTALON: `DENIM`, `PANO`, `LISO_LIGERO`, `DEPORTIVO`. CHAQUETA: `DENIM`, `CUERO`, `ACOLCHADO`, `PANO`. FALDA y VESTIDO: `LISO_LIGERO`, `SATIN`, `PUNTO`, `DENIM`. CHALECO: `ACOLCHADO`, `PUNTO`, `PANO`.
- **`formalidad`** (definido 2026-10-01): niveles ordinales `DEPORTIVO` < `CASUAL` < `SMART_CASUAL` < `FORMAL`. **Cada prenda guarda un rango** `{"min": ..., "max": ...}`; casi siempre es de un solo nivel, y abarca dos solo en las prendas versátiles. Los accesorios neutros guardan `null` y no entran al filtro. Valores por defecto según tipo y textura, editables por el usuario:
  - CAMISETA: CASUAL (`DEPORTIVO` → DEPORTIVO).
  - CAMISA: SMART_CASUAL a FORMAL (`DENIM` o `LINO` → CASUAL).
  - SUETER, CARDIGAN, ENTERIZO: CASUAL.
  - CHAQUETA: CASUAL (`PANO` → SMART_CASUAL a FORMAL; `DEPORTIVO` → DEPORTIVO).
  - ABRIGO: SMART_CASUAL.
  - CHALECO: CASUAL (`PANO` → FORMAL).
  - PANTALON: CASUAL (`PANO` → SMART_CASUAL a FORMAL; `DEPORTIVO` → DEPORTIVO).
  - SHORT: CASUAL (`DEPORTIVO` → DEPORTIVO).
  - FALDA: CASUAL (`SATIN` → SMART_CASUAL).
  - VESTIDO: CASUAL (`SATIN` → FORMAL).
  - Calzado: CASUAL sin subtipo; `ZAPATO_FORMAL` → SMART_CASUAL a FORMAL; `TACONES` → SMART_CASUAL a FORMAL; `TENIS` → CASUAL.
  - CORBATA: SMART_CASUAL a FORMAL. Demás accesorios: `null` (neutros).
- **Filtro de dress code**: una prenda pasa si su rango se cruza con el del evento; las neutras siempre pasan.
- **`clima_apto`** (definido 2026-10-01): conjunto de `FRIO`, `TEMPLADO` y `CALIDO`. Bandas en `configuracion` (documento `recomendacion`): `FRIO` < 14 °C, `TEMPLADO` 14-22 °C, `CALIDO` > 22 °C. La lluvia queda fuera del MVP.
- **Tabla (tipo, textura) → clima_apto** (definido; estática en código). Primero se aplica la regla por tipo, si existe; si no, la de la textura.
  - Por textura: `LISO_LIGERO`, `LINO`, `SATIN` → TEMPLADO y CALIDO. `DENIM`, `PUNTO`, `PANO`, `CUERO` → FRIO y TEMPLADO. `ACOLCHADO` → FRIO. `DEPORTIVO`, `OTRA` → los tres.
  - Por tipo (manda sobre la textura): ABRIGO → FRIO. SHORT → TEMPLADO y CALIDO. CAMISETA y CAMISA → los tres. Calzado: SANDALIAS → TEMPLADO y CALIDO; BOTAS → FRIO y TEMPLADO; resto o sin subtipo → los tres. BUFANDA → FRIO. Demás accesorios → los tres.
- **Regla de capas en frío** (definida 2026-10-01; regla dura del outfit): si el clima es `FRIO`, el outfit debe incluir un EXTERIOR o una prenda de TORSO_SUPERIOR con textura `PUNTO` o `ACOLCHADO`. Complementa el filtro por prenda: por eso CAMISETA y CAMISA son aptas para frío.

**19. Segmentación de prenda (u2netp).** **Definido (2026-10-01), por etapas.**
- **MVP**: pesos oficiales de u2netp (4,7 MB). El código y los pesos siguen la licencia Apache 2.0 del repositorio; fueron entrenados con DUTS, cuya licencia el autor no controla. Riesgo bajo a medio.
- **Antes de lo comercial** (o antes si el recorte falla con prendas sobre una cama o un gancho): **reentrenar u2netp** con máscaras CC BY de Fashionpedia u Open Images. Esas máscaras son de ropa puesta en personas, así que hay que mezclar fuentes o generar máscaras de prendas sueltas.
- Descartados: BiRefNet (MIT, pero ~400 MB, demasiado para gama baja) y RMBG-2.0 (CC BY-NC 4.0).

**20. Dispositivo de referencia y presupuestos.** **Definido (2026-10-01).**
- **Perfil de referencia de gama baja**: 4 GB de RAM; chip de gama baja actual (clase Helio G81, Unisoc T7250 o Snapdragon 680: 2 núcleos grandes y 6 pequeños); Android 14. Representa lo que hoy se vende en Colombia (Redmi A5, Moto G15, Galaxy A05s, Moto G06, Galaxy A15). Las metas de rendimiento se miden ahí; por debajo, la app funciona sin garantías de rendimiento.
- **Celular físico de pruebas de rendimiento**: el `D2` (Android de gama baja del equipo), si se parece al perfil.
- **Android mínimo**: 8.0 (API 26), siempre que la versión de Flutter en uso lo admita. **iOS mínimo**: 15.5 (lo exige el plugin de ML Kit para Flutter; solo 64 bits).
- **Arquitecturas Android**: compilar para `arm64-v8a` y `armeabi-v7a` (algunos Android Go corren en 32 bits). Verificar que LiteRT y ML Kit funcionen en 32 bits.
- **Presupuestos**: RAM adicional durante la inferencia ≤ 250 MB (modelos cargados de uno en uno); RAM total de la app ≤ 400 MB; peso total de los modelos ≤ 15 MB. Las metas de tiempo están en E.31.

**21. Pérdida tolerable al cuantizar a INT8.** **Definido (2026-10-01).**
- Clasificador: la exactitud de cada cabeza (tipo y patrón) cae como máximo **1 punto porcentual** frente a la versión sin cuantizar, en el conjunto de validación.
- Segmentación (u2netp): el IoU promedio cae como máximo **0,02**.
- Si se supera: primero cuantización por canal o entrenamiento consciente de la cuantización; si no alcanza, ese modelo va en **FP16**, siempre que respete el presupuesto de latencia de E.31.

## D. Recomendación

**22. Fórmula del score.** **Definido (2026-10-01); mood, estación y aprendizaje en D.25-D.26.**
- Es un **costo** (menor es mejor), compatible con el escaneo slot por slot. Cada componente es por pares de prendas o por prenda, normalizado entre 0 y 1:
  `costo = w_color·C_color + w_paleta·C_paleta + w_form·C_form + w_tex·C_tex` (más mood y estación, D.25).
- `C_color`: por pares, según la diferencia de matiz (D.23).
- `C_paleta`: por prenda, solo para TORSO_SUPERIOR, ACCESORIO_CUELLO y EXTERIOR. Usa las **probabilidades** del clasificador de colorimetría:
  - Temperatura: `p(cálido)·[prenda fría] + p(frío)·[prenda cálida]`, según el matiz de la prenda.
  - Contraste: las estaciones de contraste bajo (primavera, verano) penalizan el croma muy alto; las de contraste alto (otoño, invierno) lo admiten.
  - Las prendas neutras cuestan 0. Sin perfil de colorimetría, `w_paleta = 0`.
  - La forma exacta de la curva de croma y el corte entre matices cálidos y fríos: no definidos; configurables.
- `C_form`: por pares; 0 si los rangos de formalidad se cruzan; si no, la distancia en niveles dividida entre 3. Las neutras no cuentan.
- `C_tex`: por pares, a partir de la tabla de coocurrencia aprendida (D.26). Arranca igual para todos los pares.
- **Pesos iniciales** (en `configuracion`, documento `recomendacion`): color 0.35, paleta 0.25, formalidad 0.25, textura 0.15. Después los ajusta el vector personal de cada usuario.
- **Reglas duras**: máximo 1 prenda no lisa; capas en frío (C.18); filtros de clima y dress code.

**23. Tolerancias de matiz y neutros.** **Definido (2026-10-01); valores configurables.**
- Sobre el ángulo de matiz h° (LCh) y la diferencia Δh entre dos prendas (de 0° a 180°). Bandas armónicas, con costo 0 dentro de ellas: análoga (incluye monocromática) Δh ≤ 30°; triádica 120° ± 15°; complementaria 180° ± 20°. Fuera de las bandas el costo sube de forma lineal hasta 1 en el punto medio entre dos bandas.
- **Neutros** (costo 0 frente a cualquier color): C* < 15 (blancos, negros, grises, beige claro); o L* < 35 y C* < 30 (neutros oscuros: azul marino, marrón oscuro, oliva oscuro); o textura `DENIM`.

**24. Mapeo evento → rango de formalidad.** **Definido (2026-10-01).** Vive en `configuracion`, documento `outfits`; es filtro duro.
- `DEPORTE` (gimnasio, correr): DEPORTIVO.
- `DIA_A_DIA` (casa, universidad, diligencias): DEPORTIVO a SMART_CASUAL.
- `SALIDA_CASUAL` (amigos, cine, fiesta): CASUAL a SMART_CASUAL.
- `OFICINA` (trabajo, presentación): SMART_CASUAL a FORMAL.
- `ENTREVISTA`: SMART_CASUAL a FORMAL.
- `CENA_ELEGANTE` (cena, evento nocturno): SMART_CASUAL a FORMAL.
- `FORMAL` (boda, gala, grado): FORMAL.
- La coherencia entre prendas que pasan el filtro (por ejemplo, tenis con blazer) le toca a la fórmula del score (D.22), no al filtro.

**25. Mood y estación.** **Definido (2026-10-01).**
- **`mood`** (opcional): cada valor agrega un término de costo `w_mood·C_mood`, con `w_mood = 0.2` (0 si no hay mood).
  - `RELAJADO`: formalidad normalizada (favorece lo menos formal dentro del rango del evento).
  - `ELEGANTE`: 1 − formalidad normalizada (favorece lo más formal dentro del rango).
  - `ATREVIDO`: proporción de prendas neutras (favorece color y estampado).
  - `DISCRETO`: croma promedio normalizado (favorece neutros y análogos).
- **Estación del año**: solo si |latitud| > 23.5°. En Colombia nunca se activa, así que en el MVP queda apagada. Cuando aplique: invierno favorece tonos oscuros y verano tonos claros, con `w_estacion = 0.1`.

**26. Aprendizaje por selección.** **Definido (2026-10-01).** Job nocturno; solo usuarios con ≥ 10 selecciones nuevas; compara el outfit elegido con los descartados del mismo lote.
- **Pesos personales** (color, paleta, formalidad, textura; el mood queda global): actualización por pares tipo perceptrón. Si `costo(elegido) ≥ costo(descartado)`: `w ← w − η·(C_elegido − C_descartado)`, con `η = 0.05` (C es el vector de componentes). Después cada peso se limita a [0.05, 0.6] y se renormaliza para que la suma sea 1.
- **Tabla de coocurrencia de texturas**: por par de texturas, `pos` (aparece en el elegido) y `neg` (aparece en un descartado y no en el elegido). `q = (pos − neg) / (pos + neg + 5)`; `C_tex = (1 − q) / 2`.

**27. N de "elegir el mejor de N".** **Definido (2026-10-01): N = 3.** El motor genera unas 10 candidatas desde anclas distintas. Escoge la de menor costo y luego las siguientes que se diferencien en al menos 2 prendas principales.

**28. Prenda puente.** **Definido (2026-10-01).**
- Se cuentan las combinaciones **buenas** de la prenda candidata en su slot con las prendas existentes en los slots principales (torso superior, torso inferior o cuerpo completo, calzado, exterior; accesorios y joyería no cuentan). Buena = pasa los filtros duros y tiene un costo ≤ la mediana del costo de los outfits actuales del usuario. Mismo cálculo híbrido: batch nocturno más tiempo real.
- **Umbral**: se recomienda si abre **≥ 5** combinaciones buenas.
- **Orden**: por número de combinaciones buenas. Desempates, en orden: (1) eventos que habilita y que hoy el usuario no puede cubrir; (2) menor costo promedio de esas combinaciones; (3) menor `C_paleta`.

## E. Metas y medición

**29. Métricas de colorimetría (RNF07).** **Definido (2026-10-01); reemplaza el 85 %.**
- Acierto por capa (subtono y contraste), acierto entre las dos primeras opciones en 4 estaciones, estabilidad por persona, equidad por tono de piel (escala Monk) y comparación con las líneas base publicadas sobre Deep Armocromia (~54 % en 4 estaciones; subtono ~70 %, contraste ~76 %).
- Ivan confirma el texto exacto de RNF07 en el documento de requisitos.
- Aparte, `Criterios_de_Calidad` pide ≥ 90 % de recomendaciones que cumplan los parámetros: es otra métrica.

**30. Latencias de IA.** **Definido** en protocolos, sección 9: objetivo ≤ 5 s (RNF01) y techo de ~10 s (timeout, alineado con el criterio de calidad de generación de outfit). Aplica a outfit y a colorimetría. Consulta del clóset: ≤ 2 s (`Criterios_de_Calidad`).

**31. Digitalización de prendas: cola y metas.** **Definido (2026-10-01).**
- **Captura en cola**: cada disparo guarda la foto en el almacenamiento privado de la app (nunca en la galería) y la encola; el usuario ve una miniatura con "procesando" y sigue disparando sin esperar.
- **Procesamiento por etapas en pequeños lotes** (unas 5 fotos): primero la remoción de fondo de todo el lote, luego la clasificación, luego el color. Un solo procesador en segundo plano; los modelos se cargan de uno en uno.
- **Cola de subida aparte**, tolerante a la falta de red, con reintentos. La foto original se borra del celular cuando se confirma la subida de la prenda procesada.
- **Pantalla de revisión al final de la sesión**: cuadrícula con todo lo procesado; ahí el usuario corrige y responde las preguntas de textura de los tipos ambiguos. **Ninguna pregunta durante la captura.**
- **La cola sobrevive al cierre de la app**: su estado se guarda localmente y se retoma al abrir. En iOS, el procesamiento ocurre sobre todo con la app abierta.
- **Límites**: tope de fotos pendientes (por ejemplo 50; configurable) y pausa si el celular se calienta.
- **Metas en el dispositivo de referencia**:
  - Listo para la siguiente foto: p95 ≤ 1 s.
  - Procesamiento por prenda en el celular: p95 ≤ 2 s (unas 30 prendas en un minuto o menos).
  - Primera prenda visible en la cuadrícula: p95 ≤ 5 s después del disparo.
  - Fotos perdidas si la app se cierra: 0.
- La captura del rostro para colorimetría **no** usa la cola: es una sola foto, con consentimiento, y el usuario espera su resultado (detección y recorte ≤ 0,5 s; colorimetría con objetivo de 5 s y techo de 10 s).

## F. Datos y política para entrenar

**32. Dataset de calibración con fotos de integrantes.** **Definido (2026-10-01): sí**, solo integrantes y solo para medir estabilidad, con consentimiento escrito **específico para calibración**. Se guardan imágenes capturadas con la app, metadatos de captura y valores derivados; cifrado en una bóveda Cryptomator sobre una carpeta institucional de la universidad, fuera del repositorio, con acceso limitado a personas nombradas y borrable a petición. **El código nunca debe leer ni escribir fotos de calibración dentro del repositorio.** Celular reservado para la validación final: Android de gama media. Detalle en la política (sección 12) y en el protocolo de normalización.

**33. Datasets públicos de rostros.** **Definido (2026-10-01).**
- **Deep Armocromia**: centroides y evaluación del MVP académico (licencia de investigación; derivado de CelebA). Registrado en la procedencia.
- **MST-E**: solo evaluación (prohíbe entrenar; copyright de TONL; sin redistribución). Nunca en el repositorio.
- **FairFace** (CC BY 4.0; 108.501 rostros, 7 grupos incluido el latino): población de referencia de colorimetría (percentiles) y evaluación de equidad con anotación Monk propia. Sus etiquetas de grupo racial solo sirven para balancear la muestra, nunca como dato del producto.
- **Escala Monk** (CC BY 4.0): esquema de tonos para equidad y metadatos.
- **EasyPortrait** (variante de CC BY-SA 4.0; licencia revisada el 2026-10-29): solo para validar la segmentación facial de MediaPipe, sin entrenar y en bóveda. Sus máscaras no incluyen clase de cabello.
- **Casual Conversations v2** y **CelebAMask-HQ**: ya no son necesarios.
- **Descartados**: Roboflow "Color Analysis", Colorinsight y rostros sintéticos (SFHQ, Syn-Vis) para colorimetría. No usar modelos de visión-lenguaje como anotadores.

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
- **Recomendación (D)**: cerrada el 2026-10-01; todos los valores van en `configuracion` y se ajustan con datos.
- **Parametrizables sin bloquear**: los umbrales de A y C que siguen sin definir, como valores en `configuracion` con marcadores.
- **Decisiones rápidas**: G.36, G.40 y G.41 ya cerradas (2026-10-01).
