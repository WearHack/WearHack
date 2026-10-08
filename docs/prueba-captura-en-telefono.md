# Prueba del modo de captura en un teléfono

_Lista de comprobaciones para la primera vez que el modo de captura corre en un celular real. Cubre todo lo que quedó **sin verificar** al construirlo: la cámara real, el permiso, el EXIF, ML Kit, la red, compartir el zip y iOS. Complementa los criterios de aceptación de [`spec-modo-captura-pruebas.md`](spec-modo-captura-pruebas.md) (sección 5) y los puntos técnicos de su sección 8._

**Cómo usarla.** Hazla en este orden, con el **D2** (Android de gama baja) primero: es el perfil de referencia de rendimiento. Marca cada fila con ✔ o ✘ y, si falla, anota **qué viste**, no solo que falló. Al final hay una plantilla para el registro. Un ✘ no significa que el código esté mal: puede ser una decisión que falta (por ejemplo los márgenes), y para eso están las columnas de "si falla".

> **Antes de empezar, dos advertencias.**
> 1. **Los tres márgenes del recorte siguen sin definirse** (`respuestas-claude-code.md`, A.8). Sin ellos la app no recorta y por tanto no captura. El bloque B es el procedimiento para elegirlos; hazlo antes de capturar nada que quieras conservar.
> 2. **No uses iOS con fotos reales de calibración todavía.** Falta excluir la carpeta de las copias de iCloud y de iTunes (ver bloque H). En Android la copia automática ya está desactivada.

---

## 0. Qué necesitas

| Cosa | Para qué | Nota |
|---|---|---|
| El **D2** (Android, gama baja) y, si hay, el **D3** y un **D1** (iPhone) | Probar en los tres | D3 está reservado para la validación final: pruébalo solo en lo mínimo (bloque A) |
| Cable USB y **depuración USB** activada | Instalar y leer archivos con `adb` | `adb` viene en la carpeta `platform-tools` del SDK de Android. No está en el PATH de esta máquina: añádelo o llámalo con la ruta completa |
| El repo en esta rama, con Flutter y Python | Compilar y correr los scripts | `JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=C:\temp-java-sockets` en Windows. Si la build muere con "out of memory", reintenta o baja el heap de `android/gradle.properties` solo para esa build (ver el README del módulo) |
| La **bóveda Cryptomator** montada y `~/.wearhack/importar_lote.json` configurado | Importar el lote | Ver `tools/captura/README.md` |
| La **tarjeta gris** fotográfica | Las tomas R1 | Está pendiente de comprar en el protocolo. Para probar el flujo basta cualquier objeto gris |
| Una hoja con **texto grande** impreso | Prueba del espejo (C11) | |
| Una regla o cinta métrica | Los 30-40 cm | |
| **PCAPdroid** (app de Android) o similar | Ver las conexiones de red de la app (F3) | Sugerencia, no verificada aquí. Sin ella, F3 se hace a medias con el consumo de datos |

Paquete de la app en Android: `app.wearhack.wearhack`. Los comandos `run-as` solo funcionan con una build **de depuración**.

### Comandos que se repiten

Compilar e instalar (sustituye los `...` por tus márgenes, ver bloque B):

```bash
cd client
flutter run -d <id-del-celular> --dart-define=CAPTURA_PRUEBAS=true \
  --dart-define=RECORTE_MARGEN_SUPERIOR=... \
  --dart-define=RECORTE_MARGEN_INFERIOR=... \
  --dart-define=RECORTE_MARGEN_LATERAL=...
```

Ver lo que hay guardado, sin salir del celular:

```bash
adb shell run-as app.wearhack.wearhack ls -la app_flutter/captura_pruebas/tomas
```

Sacar un recorte al PC para verlo (cambia el nombre):

```bash
adb exec-out run-as app.wearhack.wearhack cat app_flutter/captura_pruebas/tomas/P3_LEDC_D2_R1_G_recorte.png > recorte.png
```

Si `app_flutter/captura_pruebas` no existe, la carpeta está en otro sitio: `adb shell run-as app.wearhack.wearhack find . -name captura_pruebas`.

---

## A. Arranque, permisos y el flag

| # | Qué hacer | Debería pasar | Si falla, anota | ✔ |
|---|---|---|---|---|
| A1 | Instala una build **con** `CAPTURA_PRUEBAS=true` y ábrela | La pantalla de esqueleto trae el botón **"Captura de pruebas (build interna)"** | Si no está: ¿llegó el flag? | ☐ |
| A2 | Instala una build **sin** el flag (`flutter build apk --release`) y ábrela | **No hay botón, menú ni gesto** que abra el modo (spec 5, criterio 1) | Cualquier forma de llegar al modo | ☐ |
| A3 | En A1, abre el modo y **deniega** el permiso de cámara | Mensaje "No se pudo abrir la cámara: …", sin cierre de la app, sin botón de capturar | Si se cierra: la traza de `adb logcat` | ☐ |
| A4 | Concede el permiso desde Ajustes y vuelve | La cámara se abre | | ☐ |
| A5 | **Permisos que pidió**: en Ajustes → Apps → permisos | Solo **Cámara**. Ni micrófono, ni fotos, ni almacenamiento | Los que aparezcan | ☐ |
| A6 | `adb shell dumpsys package app.wearhack.wearhack \| grep -E "permission\|allowBackup\|ALLOW_BACKUP"` | Declarados: `CAMERA`, `INTERNET`, `ACCESS_NETWORK_STATE` (los dos últimos por bibliotecas). Sin `RECORD_AUDIO`, sin `*_EXTERNAL_STORAGE`. Sin el indicador `ALLOW_BACKUP` | Lo que sobre | ☐ |
| A7 | Una build **sin** los `RECORTE_MARGEN_*`: abre una toma y pulsa capturar | Mensaje "Falta configurar el recorte: falta RECORTE_MARGEN_SUPERIOR; …" y **nada guardado** | Si guarda algo, o el mensaje no nombra el parámetro | ☐ |
| A8 | En el inicio, prueba las 8 combinaciones de persona, celular y autorización | "Continuar" solo se enciende con las **tres** | La combinación que lo enciende de más | ☐ |

---

## B. Elegir los márgenes del recorte

Es la decisión que falta (A.8). La foto completa se guarda siempre, así que un margen malo se corrige **regenerando** el recorte; no se pierde nada. Pero conviene fijarlos antes de la sesión de 270 fotos.

1. Compila con un juego de márgenes, captura **3 tomas** con personas distintas (pelo corto, largo, con flequillo) y saca los recortes al PC (comando de arriba).
2. Repite con otro juego. Como **punto de partida para mirar** (no son una recomendación; no tengo datos que la respalden), prueba algo como `0.35 / 0.10 / 0.15`, `0.50 / 0.15 / 0.25` y `0.70 / 0.20 / 0.35` (superior / inferior / lateral, fracciones del recuadro del rostro).
3. Mira cada recorte con estos criterios:

| # | Criterio | ✔ |
|---|---|---|
| B1 | El **cabello encima de la frente** entra completo (el protocolo lo necesita para el eje de contraste) | ☐ |
| B2 | Entran el **mentón** y las **orejas** | ☐ |
| B3 | No sobra tanto fondo que domine el recorte | ☐ |
| B4 | Con el rostro cerca del borde de la foto, el recorte **no falla** y queda más pequeño por ese lado | ☐ |
| B5 | El resultado es parecido entre personas | ☐ |

**Qué anotar:** el juego elegido, y el motivo. Va a `respuestas-claude-code.md` (A.8) y a la fila "Umbrales de calidad y percentiles de muestreo" de `procedencia-datos-wearhack.md`. **Pendiente de saber:** si el recuadro de ML Kit cubre el cabello o solo de las cejas al mentón. Lo supongo, no lo verifiqué: B1 lo responde.

---

## C. Flujo de captura (D2)

| # | Qué hacer | Debería pasar | Si falla, anota | ✔ |
|---|---|---|---|---|
| C1 | Elige P1, D2, marca la autorización y entra | Cuadrícula de **15 casillas** (5 luces × 3 repeticiones), todas pendientes; solo las R1 dicen "con tarjeta" | | ☐ |
| C2 | Toca `LEDC R1` y mira el aviso | "Pon la tarjeta gris junto al rostro". Óvalo visible, vista previa **de cámara frontal** | Si la vista sale girada o estirada | ☐ |
| C3 | Toma la foto. **Cronometra** desde el toque hasta ver la casilla marcada | Vuelve a la cuadrícula con la casilla "hecha" y `1/15` | Tiempo, y si la pantalla se congela | ☐ |
| C4 | Toca `LEDC R2` y `R3` | "Retira la tarjeta gris" en las dos | | ☐ |
| C5 | Toca el botón de capturar **dos veces seguidas** | Una sola foto: el botón se apaga mientras guarda | Si salen dos | ☐ |
| C6 | Apunta a una pared, **sin rostro** | "No se vio un rostro…", nada guardado (`ls` de la carpeta), botón disponible otra vez | Si guarda una toma sin rostro | ☐ |
| C7 | **Dos personas** en la foto | Funciona y recorta el rostro más grande | Si recorta el equivocado | ☐ |
| C8 | Foto muy **oscura** (`BAJ`) y muy **brillante** (frente a una ventana) | Se guardan; si pusiste umbrales de calidad, sale el aviso con la razón concreta y "Conservar / Repetir" | Si no salta el aviso con umbrales puestos | ☐ |
| C9 | Toca una casilla **ya hecha** | Pregunta "¿Reemplazar la toma?". Cancelar no abre la cámara; confirmar deja **una sola** toma con la foto nueva | Si quedan dos, o si cancelar la reemplaza | ☐ |
| C10 | **Gira el teléfono** a horizontal durante la captura y toma una foto | La foto y el recorte salen **derechos**. El inspector (D1) no marca "no cabe en la foto orientada" | Cómo sale el recorte (girado 90°, de lado) | ☐ |
| C11 | **Espejo:** sostén la hoja con texto junto a tu cara y toma una foto. Mira la foto y el recorte en el PC | Anota si el texto sale **legible o al revés**. No hay respuesta correcta: es un dato | Cuál de los dos. **No lo corrijas**: voltear o no es decisión del protocolo y se registra | ☐ |
| C12 | Mientras estás en la cámara: bloquea la pantalla, o pasa a otra app, y vuelve | La cámara se recupera, sin cierre, y las tomas anteriores siguen | Si queda negra o se cierra | ☐ |
| C13 | **Cierre brusco:** pulsa capturar y fuerza el cierre de la app (Ajustes → Forzar detención) casi a la vez. Reabre | La toma está completa o **no está**. Intenta **exportar** | Si exportar dice "El lote tiene problemas: sobra el archivo …" → **es lo esperado** si el cierre cayó a medias. Vuelve a tomar **esa misma toma**: la sobreescribe y exportar debe funcionar | ☐ |
| C14 | Revisa que **no** hay fotos en la galería ni en `DCIM` (F1) | | | ☐ |

> **C13 es una hipótesis mía, no un hecho verificado.** Por cómo está escrito el guardado (el `.json` va el último), un cierre a medias deja archivos huérfanos, y exportar se niega nombrándolos. La salida es repetir esa toma. Si en la práctica aparece más de una vez, vale la pena una limpieza de huérfanos; eso es una decisión tuya y no está hecho.

---

## D. Perfil de color y EXIF (lo que solo se ve con fotos reales)

Toma **6 fotos** en el D2 (varias luces y las tres repeticiones), exporta, trae el zip al PC y corre:

```bash
python tools/captura/importar_lote.py RUTA/lote_xxxxxxxx.zip --solo-verificar
python tools/captura/inspeccionar_lote.py RUTA/lote_xxxxxxxx.zip
```

| # | Qué mirar en la salida | Debería pasar | Anota | ✔ |
|---|---|---|---|---|
| D1 | `importar_lote.py` | Sale con 0, trae el hash global y el resumen correcto | Cualquier problema que liste | ☐ |
| D2 | `Sin hallazgos` en el inspector | Salida 0 | Cada hallazgo, textual | ☐ |
| D3 | **Perfil ICC de la foto** (`Con perfil ICC`, `perfiles:`) | **Anota cuál sale** en cada celular: `Display P3`, `sRGB…`, o sin perfil. Si sale sin perfil, la app **asume sRGB** y lo anota en el JSON | El nombre exacto. En un celular de gama baja lo normal es sRGB o ninguno | ☐ |
| D4 | `perfil_color.foto` frente al perfil real | Coinciden (el inspector lo comprueba y lo marca si no) | | ☐ |
| D5 | **El recorte** | Sin perfil incrustado, RGB de 8 bits, `perfil_color.recorte = "sRGB (convertido por la app)"` | | ☐ |
| D6 | **EXIF**: `Con ISO`, `con exposición`, `con balance de blancos` | Debería haber valores. Anota **cuántas de las 6** los traen | Si salen en cero, esos campos quedarán `null` en todo el lote | ☐ |
| D7 | **Orientaciones EXIF** | Anota los valores (1, 6, 8, …). El recuadro del rostro **cabe** en todas | Si el inspector marca "no cabe", la orientación se manejó mal | ☐ |
| D8 | Abre la foto y el recorte en un visor **con gestión de color** | Los dos se ven **del mismo color** | Si el recorte se ve distinto (más apagado o más saturado) | ☐ |

**Por qué D3 importa:** si un celular de gama media o alta entrega Display P3 y la app lo convierte bien, se ve en D4 y D5. Si entrega P3 y la app lo tratara como sRGB, el color medido se desplaza (a\* unas 4,5 unidades y b\* unas 3,4 en un tono de piel, según mi medición con un perfil sintético).

---

## E. Exportar, importar y borrar

| # | Qué hacer | Debería pasar | Si falla, anota | ✔ |
|---|---|---|---|---|
| E1 | En la cuadrícula, **Exportar lote** | Se abre la hoja de compartir del sistema y el aviso "Lote exportado: lote_xxxxxxxx.zip" | Si no abre la hoja, o si el zip no llega | ☐ |
| E2 | Pásalo al PC (USB, AirDrop o `adb exec-out run-as … cat …/exportaciones/lote_….zip > lote.zip`) | Llega completo | | ☐ |
| E3 | `importar_lote.py` a la bóveda | Sale con 0, copia **todas** las piezas más el manifiesto, y muestra "Para habilitar Borrar, escribe: XXXXXXXX" | Si falla en la bóveda real (spec: no verificado con Cryptomator) | ☐ |
| E4 | Comprueba el contenido de la bóveda | Las piezas esperadas, sin carpeta `.…importando` colgada | Una carpeta oculta con ese nombre | ☐ |
| E5 | **Borrar** con un texto equivocado | Mensaje "No coincide con el hash…", el diálogo sigue abierto, **no se borró nada** | | ☐ |
| E6 | Toma **una foto más** *después* de exportar. Intenta borrar con el prefijo de E3 | **Se rechaza**: el estado cambió y el prefijo viejo ya no vale | Si borra, se perdió una toma que nunca se importó | ☐ |
| E7 | Exporta de nuevo, importa, y borra con el prefijo nuevo | La cuadrícula queda en `0/15` | | ☐ |
| E8 | Tras borrar: `adb shell run-as app.wearhack.wearhack find app_flutter/captura_pruebas` y `ls cache` | **Sin ningún archivo** de fotos en ninguno de los dos | Lo que quede | ☐ |
| E9 | Un lote **completo** (los 90 de un celular, o los que puedas): mide el tiempo de exportar y el tamaño del zip | Anota las dos cifras. Mi estimación en un PC es ~290 MB de lote y otro tanto de zip | El tiempo real en gama baja y si hay espacio | ☐ |

---

## F. Privacidad

| # | Qué hacer | Debería pasar | Si falla, anota | ✔ |
|---|---|---|---|---|
| F1 | **Galería.** Antes y después de capturar: abre la app Galería/Fotos, y `adb shell ls -la /sdcard/DCIM/Camera /sdcard/Pictures` | **No aparece ninguna foto nueva** (spec 5, criterio 4) | Dónde apareció | ☐ |
| F2 | **Temporales.** Tras capturar: `adb shell run-as app.wearhack.wearhack ls -la cache` | **Ningún JPEG** de las fotos. El plugin de cámara deja un archivo temporal y la app lo borra | Los archivos que queden | ☐ |
| F3 | **Red.** Con el consumo de datos por app anotado, y **PCAPdroid** activo: haz una sesión con captura **y** exportar. Repite en **modo avión** | La app **no abre ninguna conexión** (spec 5, criterio 3) | **Cada conexión que veas, con su destino.** Es lo más probable que falle: ML Kit trae el transporte de datos de Google (`datatransport`) para sus métricas de uso | ☐ |
| F4 | **Copia de seguridad** (Android): `adb shell dumpsys package app.wearhack.wearhack \| grep -i backup` | Sin `ALLOW_BACKUP` | | ☐ |
| F5 | Ajustes → Cuentas → Copia de seguridad, y mira si la app aparece entre las que se respaldan | No aparece | | ☐ |

**Sobre F3.** Mientras no se compruebe con una captura de red, la recomendación es **hacer las sesiones en modo avión**. Si F3 muestra conexiones, la decisión de qué hacer (quitar `INTERNET` solo para una variante de esta build, o aceptar las métricas de ML Kit) es tuya y hay que anotarla en `procedencia-datos-wearhack.md`.

---

## G. Rendimiento (en el D2)

Las metas salen de `respuestas-claude-code.md` (A.20 y E.31). El D2 debería parecerse al perfil de referencia (4 GB de RAM, Android 14, chip de gama baja); anota cuánto se aleja.

| # | Qué medir | Cómo | Meta | Mi expectativa | Resultado |
|---|---|---|---|---|---|
| G1 | **Detección y recorte** de una foto | Cronometra C3, o usa grabación de pantalla | ≤ 0,5 s (producto, E.31) | **Probablemente NO se cumple**: en un PC, decodificar 12 MP y recortar tarda ~1 s, y en gama baja será varias veces eso. Si falla, es un dato para el **producto** (decodificar a menor resolución), no un fallo del modo de captura, donde lo que se guarda es la foto completa | |
| G2 | **RAM** durante la captura | `adb shell dumpsys meminfo app.wearhack.wearhack` antes y justo después de capturar. Mira `TOTAL PSS` | RAM total ≤ 400 MB; adicional por inferencia ≤ 250 MB | Si el pico supera lo previsto, anota la cifra | |
| G3 | **Estabilidad** en una sesión larga | 15 tomas seguidas | Sin cierres, sin que la cámara se ponga negra | | |
| G4 | **Calentamiento** | Al terminar las 15 tomas | Sin avisos de temperatura | | |
| G5 | **Arquitectura** | Si hay un celular de 32 bits (armeabi-v7a), instala la build de depuración (trae las dos) | Abre y captura | No verificado: ML Kit trae el `.so` de 32 bits | |
| G6 | **Guía de distancia en vivo** (opcional) | Compila con `CAPTURA_GUIA_EN_VIVO=true` | Muestra el ancho del rostro y cambia al moverte; no congela la captura | **Sin verificar**: la rotación de los fotogramas y el rendimiento. Apagada por defecto. Si sale bien, es lo que permite calibrar `DISTANCIA_ANCHO_<celular>` a 30-40 cm | |

---

## H. iOS (D1)

> **No hay una build de iOS todavía y no se ha compilado nunca.** Esto necesita un Mac y se hace **después** de A-G en Android.

**Antes de compilar:**

- [ ] `ios/Podfile` (Flutter lo genera en la primera build): `platform :ios, '15.5'` y excluir `armv7` (requisitos de ML Kit).
- [ ] Firma con una cuenta de Apple Developer.
- [ ] **Excluir `Documents/captura_pruebas` de las copias de iCloud y de iTunes** (`NSURLIsExcludedFromBackupKey`, código nativo, **sin hacer**). Hasta entonces, **solo fotos de prueba de integrantes que acepten ese riesgo**, no el conjunto real.

| # | Qué comprobar | Debería pasar | Anota | ✔ |
|---|---|---|---|---|
| H1 | Pide el permiso de cámara con el texto de `NSCameraUsageDescription` | Aparece ese texto | Si la app se cierra al abrir la cámara, falta la clave | ☐ |
| H2 | **Formato de la foto** | `.jpg` (el plugin usa JPEG por defecto; HEIC solo si se pide) | Si llega `.heic`, el inspector no lo analiza | ☐ |
| H3 | **Perfil ICC** del lote en el inspector | **`Display P3`** (spec 5, criterio 6) y `perfil_color.foto` coincide | Qué sale. Si sale sin perfil, el nivel 0 no se está cumpliendo en iPhone | ☐ |
| H4 | La casilla **True Tone o Night Shift** | Queda en el JSON de las tomas | | ☐ |
| H5 | EXIF (ISO, exposición, balance de blancos) | Presentes | Cuántas | ☐ |
| H6 | Espejo de la cámara frontal (C11) | Anota el resultado | | ☐ |

---

## I. Cierre

**Registro.** Copia esta tabla y llénala por celular:

| Bloque | Celular | Resultado | Evidencia (captura, salida del inspector, cifra) | Decisión pendiente |
|---|---|---|---|---|
| A | | | | |
| B | | | | Márgenes elegidos: |
| C | | | | ¿Voltear la cámara frontal? |
| D | | | | |
| E | | | | |
| F | | | | ¿Qué hacer con las conexiones de ML Kit? |
| G | | | | |
| H | | | | |

**Qué se corrige en los documentos con lo que salga:**

- `respuestas-claude-code.md` **A.8**: los márgenes y, si sale, el mínimo de píxeles por región.
- `procedencia-datos-wearhack.md`, fila de **ML Kit**: dice que depende de Google Play Services, y lo que se verificó es distinto. El plugin de Flutter (`google_mlkit_face_detection`) usa la variante con el **modelo incluido en la app** (`blazeface.tfl` dentro del APK), no depende de Play Services; pero ML Kit trae `com.google.android.datatransport` y **puede enviar métricas de uso a Google**. F3 dice si lo hace.
- `spec-modo-captura-pruebas.md` §8: las respuestas a los puntos 1 (parámetros de cámara: D6), 2 (ICC: D3 a D5), 3 (formato en iOS: H2), 4 (orientación y espejo: C10, C11, D7) y 5 (espacio y tiempo de exportación: E9).

**Si algo falla, qué mirar primero:**

| Síntoma | Primer sitio donde mirar |
|---|---|
| El recorte sale mal | Los márgenes (B) y `adb logcat` |
| Exportar se niega | El mensaje nombra el archivo huérfano o corrupto: repite esa toma |
| `importar_lote.py` rechaza el lote | Su salida lista todos los problemas, no solo el primero |
| El inspector marca "no cabe en la foto orientada" | La orientación EXIF (D7) |
| La build muere con "out of memory" | Reintenta; la máquina tiene 7,7 GB y Gradle pide 8 |
