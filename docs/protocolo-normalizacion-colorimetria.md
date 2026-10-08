# Protocolo de evaluación — Normalización de color para colorimetría (WearHack)

_2026-10-01 · Estado: protocolo definido; ejecución pendiente._

## 1. Objetivo

Responder dos preguntas antes de elegir una técnica de corrección:

1. **Línea base**: cuánto varía hoy la medición de color (Lab de piel, cabello e iris) de una misma persona según la luz y el celular.
2. **Elección**: qué técnica reduce esa variación sin alterar el orden de tonos de piel ni perjudicar a ningún grupo de tono.

## 2. Requisitos base de la captura (nivel 0, obligatorios en el producto)

- **Gestión de color**: leer el perfil ICC de la imagen y convertir a RGB lineal, luego a XYZ, luego a Lab con blanco D65. Cualquier corrección de balance se aplica en RGB lineal, nunca sobre valores con gamma. Los iPhone suelen capturar en Display P3: asumir sRGB desplaza a* y b*.
- **Requisito del cliente**: si recorta y recodifica la imagen, debe convertirla antes a sRGB o conservar el perfil ICC. El servidor nunca debe recibir colores sin saber en qué espacio están.
- **Formato del recorte**: PNG o JPEG de alta calidad, con un tamaño mínimo del rostro en píxeles (valor por fijar con estos datos).
- **Controles de calidad**: porcentaje de píxeles quemados o negros en la piel, desenfoque y tamaño del rostro. Si fallan, la app sugiere repetir la foto con una recomendación concreta, sin obligar.
- **Variables relativas**: contraste como diferencia de L* entre regiones, más a/L y b/L.
- **Cámara propia de la app**, para evitar los modos de belleza de la cámara del sistema.

## 3. Datos

### 3.1 MST-E (Google)

19 personas que cubren los 10 tonos de la escala Monk, fotografiadas en un lapso de 4 horas, con un subconjunto en condiciones de luz difíciles.

- **Mide**: el efecto de la luz y la equidad por tono.
- **No mide**: el procesamiento de los celulares, porque son fotos con cámara profesional.
- **Requisito previo**: leer y cumplir sus términos de uso.

### 3.2 Sesión de captura del equipo (decidida)

| Variable | Valor |
|---|---|
| Personas | Los 6 integrantes, mayores de 18, con consentimiento específico de calibración |
| Luces (5) | `VEN` ventana indirecta · `LEDC` LED cálido (bombilla amarilla) · `LEDF` LED o fluorescente frío (oficina) · `MIX` ventana + bombilla · `BAJ` poca luz (una lámpara de noche) |
| Celulares (3) | Al menos un iPhone, un Android de gama media y un Android de gama baja |
| Repeticiones (3) | `R1` con tarjeta gris en el encuadre; `R2` y `R3` sin tarjeta |
| Total | 6 × 5 × 3 × 3 = **270 fotos** |
| Condiciones fijas | Mismo día, en una ventana de ~2 horas; sin maquillaje (o el mismo en todas las fotos); 30-40 cm de distancia; rostro centrado; cámara frontal de la app |
| Metadatos por foto | Persona (seudónimo), luz, celular, repetición, presencia de tarjeta, hora, True Tone o Night Shift activos |

**Tarjeta gris fotográfica** (decidida): solo para el banco de pruebas, nunca en el producto. Va junto al rostro, fuera de la región que se recorta. Aparece solo en `R1` porque un objeto gris en la escena ayuda al balance automático del celular: si estuviera en todas las fotos, la línea base saldría mejor de lo que es en uso real. Con `R1` frente a `R2`/`R3` además se puede medir ese efecto.

**Archivo maestro**: en las pruebas se guarda la foto completa, además del recorte, para poder volver a procesar.

**Convención de nombres** (propuesta): `P3_LEDC_D2_R1_G.png` (persona, luz, celular, repetición, `G` con tarjeta / `N` sin ella), con un archivo JSON de metadatos al lado.

## 4. Técnicas a comparar

| Código | Técnica |
|---|---|
| T0 | Sin corrección (línea base) |
| T1 | Blanco del ojo (esclerótica) como referencia |
| T2 | Brillos especulares de la piel y reflejo de la córnea (modelo dicromático) |
| T3 | Modelo aprendido de constancia de color, con licencia compatible |
| REF | Corrección con la tarjeta gris (mejor caso posible; solo en `R1`) |
| T4 | Pantalla como flash con dos fotos. **Solo si T1-T3 no alcanzan**; requiere código nativo para bloquear exposición y balance de blancos |

## 5. Métricas

| Código | Métrica | Definición |
|---|---|---|
| M1 | Dispersión por persona | ΔE00 entre las medianas Lab de cada región para la misma persona en distintas fotos; percentiles 50 y 90, por región |
| M2 | Cambio de decisión | Porcentaje de pares de fotos de la misma persona con distinto subtono o contraste. Frontera provisional para esta prueba: la mediana del grupo |
| M3 | Error de estimación de la luz | Ángulo, en grados, entre la luz estimada y la que indica la tarjeta gris (fotos `R1`) |
| M4 | Orden de tonos (MST-E) | Correlación de Spearman entre el tono de piel corregido (L* e ITA, ángulo tipológico individual) y las etiquetas de la escala Monk |
| M5 | Equidad | M1 y M2 separadas por grupos de tono: 1-3, 4-7 y 8-10. El grupo 4-7 merece atención especial: un estudio de la Universidad de Stellenbosch encontró ahí la menor precisión de estimación del tono |
| M6 | Rechazo de calidad | Porcentaje de fotos que fallan los controles de calidad, por luz y por celular |

Además, se separa el ruido de repetición (entre `R2` y `R3` en la misma condición) del efecto de la luz y del celular.

## 6. Criterios de éxito (decididos antes de ver resultados)

- **Principal**: M2 ≤ 10 % para subtono y para contraste, entre las tres luces normales (`VEN`, `LEDC`, `LEDF`), en todos los grupos de tono.
- **Equidad**: diferencia de M2 entre grupos de tono ≤ 5 puntos porcentuales.
- **Secundario**: M1 de piel (percentil 90) baja al menos un 30 % respecto a T0.
- **Luces difíciles** (`MIX`, `BAJ`): se reportan, pero no bloquean. Sirven para calibrar los controles de calidad y los consejos de captura.

Se elige la técnica más simple que cumpla los criterios. Si ninguna de T1-T3 los cumple, se evalúa T4.

## 7. Análisis y reproducibilidad

- **Datos reservados (decidido)**: el **Android de gama media** se aparta y no se usa hasta confirmar la técnica elegida. Se desarrolla con la gama baja (el objetivo más difícil) y con el iPhone (obliga a resolver Display P3 desde el principio).
- Scripts en Python reproducibles, con semilla fija, que producen una tabla de resultados por técnica y por métrica.
- La segmentación y el muestreo son los mismos del servicio de Colorimetría, para que lo medido sea lo que el producto hará.

## 8. Datos y consentimiento

Según `politica-datos-colorimetria-wearhack.md`, sección 12:
- Consentimiento específico de calibración.
- Almacenamiento (decidido): bóveda cifrada con Cryptomator sobre una carpeta institucional de la universidad; el proveedor solo ve archivos cifrados; acceso limitado a personas nombradas.
- Borrado a petición.

MST-E se usa según sus términos.

## 9. Preparación pendiente

- [ ] Comprar la tarjeta gris fotográfica.
- [ ] Leer los términos de uso de MST-E.
- [x] Redactar el consentimiento específico de calibración (borrador revisado por el equipo; pendiente revisión legal y completar marcadores).
- [x] Elegir qué celular queda reservado: Android de gama media.
- [ ] Implementar el nivel 0 y el modo de captura de pruebas en la app: especificación lista en `spec-modo-captura-pruebas.md`.
- [ ] Preparar los scripts de análisis (M1-M6).
- [x] Definir la ubicación del almacenamiento cifrado: bóveda Cryptomator en carpeta institucional.
