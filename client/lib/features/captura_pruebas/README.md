# captura_pruebas

Modo de captura para **calibrar la colorimetria** (270 fotos: 6 personas x 5 luces
x 3 celulares x 3 repeticiones). Es una herramienta interna, no una funcion del
producto. La especificacion completa esta en
[`docs/spec-modo-captura-pruebas.md`](../../../../docs/spec-modo-captura-pruebas.md).

**Estado:** la logica (guardar, metadatos, manifiesto, exportar, borrar), las tres
pantallas y la camara estan hechas y compilan en Android. **Nada de esto se ha
probado en un telefono**: las pantallas se prueban con una camara falsa y el
almacen real, y la camara real solo se comprueba con un dispositivo. Ver "Lo que NO
esta verificado".

## Como correrlo en un telefono

El modo solo existe si se compila con el flag. Sin el, ni un simbolo ni un texto del
modo llegan al binario (comprobado en `libapp.so` de un APK de release).

```bash
flutter run --dart-define=CAPTURA_PRUEBAS=true
```

Los margenes del recorte salen **provisionales** (ver la tabla); para cambiarlos se
pasan al compilar con `--dart-define=RECORTE_MARGEN_SUPERIOR=...` y los otros dos.

| Define | Para que | Sin el |
|---|---|---|
| `CAPTURA_PRUEBAS=true` | Enciende el modo y el boton que lo abre | El modo no existe |
| `RECORTE_MARGEN_SUPERIOR`, `_INFERIOR`, `_LATERAL` | Margenes del recorte, como fraccion del tamano del rostro detectado. **Provisionales**, fijados por el responsable de la spec para la fase de captura (no salen de una medicion): `0.6`, `0.15` y `0.3` | Valen esos tres valores (`core/recorte/configuracion_recorte.dart`) |
| `RECORTE_ANCHO_MINIMO_ROSTRO_PX`, `CALIDAD_MAX_QUEMADOS_PCT`, `CALIDAD_MAX_NEGROS_PCT`, `CALIDAD_NITIDEZ_MINIMA` | Umbrales de los controles de calidad. Opcionales | Se miden, pero nunca fallan |
| `DISTANCIA_ANCHO_D1`, `_D2`, `_D3` (`"380-520"`) | Rango de ancho de rostro (px) que equivale a 30-40 cm, calibrado una vez por celular | La guia dice "sin calibrar" |
| `CAPTURA_GUIA_EN_VIVO=true` | Enciende la guia de distancia en vivo | Apagada: la camara solo toma fotos |

La guia en vivo esta **apagada por defecto** porque pasar fotogramas a ML Kit con la
rotacion correcta no se ha verificado, y la captura de las 270 fotos no debe depender
de algo sin probar. Para calibrarla: encenderla, poner el rostro a 30-40 cm, anotar el
ancho que muestra la pantalla, y pasarlo en `DISTANCIA_ANCHO_<celular>`.

**Recomendacion: pon el celular en modo avion durante la sesion de captura.** Ver
"Red" abajo.

## Pantallas

1. **Inicio** (`ui/pantalla_inicio.dart`): persona (`P1` a `P6`), celular (`D1` a `D3`),
   la casilla de autorizacion firmada y la de True Tone o Night Shift. Nada viene
   elegido de antemano. Sin persona, celular y autorizacion, "Continuar" esta apagado.
2. **Cuadricula** (`ui/pantalla_cuadricula.dart`): las 15 tomas (5 luces x 3
   repeticiones) de esa persona con ese celular, y los botones Exportar y Borrar.
3. **Captura** (`ui/pantalla_captura.dart`): camara frontal, ovalo de encuadre, aviso de
   la tarjeta gris (R1 la lleva, R2 y R3 no) y el boton. Si un control de calidad no
   pasa, la toma ya esta guardada y se sugiere repetir con una recomendacion concreta,
   sin obligar.

Las pantallas no importan ningun plugin: reciben la camara, el lector del dispositivo
y la hoja de compartir por `DependenciasCaptura` (`ui/dependencias.dart`). Las piezas
que si tocan la plataforma estan en `lib/platform/captura_pruebas/`.

## Parametros de camara

El plugin `camera` no expone ISO, exposicion ni balance de blancos en la foto, asi que
se leen del **EXIF** del JPEG (`parametros_exif.dart`). La spec solo dice "exposicion",
"iso" y "balance_blancos"; se interpretaron asi:

- `exposicion`: el **tiempo de exposicion en segundos** (no la compensacion).
- `iso`: la sensibilidad ISO.
- `balance_blancos`: `"auto"` o `"manual"`. El tag solo distingue esos dos modos.

Lo que el EXIF no traiga queda en `null`.

## Reglas que no se negocian

1. **Solo builds internas.** Se activa con `--dart-define=CAPTURA_PRUEBAS=true`
   (`Configuracion.capturaPruebas`). Sin el flag el codigo no es alcanzable.
2. **Sin red.** Ningun import de red; lo comprueba `captura_pruebas_reglas_test`
   con una lista blanca de imports. Falta la comprobacion con un proxy en un
   celular real.
3. **Fuera de la galeria.** Todo va al almacenamiento privado de la app.
4. **Nunca en el repositorio.** `AlmacenCapturas` se niega a trabajar dentro de una
   carpeta con `.git` en alguno de sus padres. Los tests usan el directorio
   temporal del sistema y fotos sinteticas.
5. **Mismo recorte que el producto.** `ServicioCapturaPruebas` no recibe un recorte
   hecho por otro: recibe el `FaceCropper` y lo llama el mismo.

## Archivos

| Archivo | Que hace |
|---|---|
| `modelos.dart` | Luz, repeticion, celular, seudonimo `P1` a `P6`, e `IdToma` (el nombre de los archivos) |
| `metadatos.dart` | El JSON de cada toma (esquema 1) y `validarMetadatos`, que es estricto |
| `almacen_capturas.dart` | Guarda y lista tomas, y `verificarIntegridad` |
| `servicio_captura.dart` | Exige la autorizacion firmada, llama al recorte real y guarda |
| `lote.dart` | Manifiesto, hash global, `exportarLote` y `borrarLote` |

## Disposicion en disco

```
<raiz privada>/
  tomas/            P3_LEDC_D2_R1_G_foto.jpg   la foto tal como la dio la camara
                    P3_LEDC_D2_R1_G_recorte.png
                    P3_LEDC_D2_R1_G.json       se escribe el ultimo
  exportaciones/    lote_P3_<8 caracteres>.zip
```

Una toma "existe" cuando existe su `.json`. La foto **no se recodifica**: asi
conserva su perfil de color (ver `lib/core/color/`).

**Tomas incompletas.** La foto o el recorte sin su `.json`, o un `.tmp`, es lo que deja un
cierre a medias (o un reemplazo cortado). No cuentan como toma y `exportarLote` se niega
mientras estan. Al abrir el modo, la pantalla de inicio las detecta y pregunta si se
borran (`Conservar` o `Borrar`); sin confirmacion no se borra nada y ninguna toma
completa se toca.

## Exportar y borrar

**El lote es por persona**: las 15 tomas de un seudonimo (un celular lleva hasta 6 lotes,
90 tomas). **Exportar** genera `lote_<persona>_<8 del hash>.zip` solo con los archivos
de esa persona, y su hash global es el de ese zip. **Borrar** borra solo el lote de la
persona (sus tomas y sus zip) y exige el prefijo del hash **de ese lote**; las demas
personas no se tocan.

El zip es **plano** (sin carpetas) y trae `manifiesto.json`. El hash global es:

```
SHA-256 del texto formado por una linea  "<sha256>  <nombre>\n"  por archivo
(dos espacios, como sha256sum), ordenadas por nombre en orden ordinal.
El manifiesto no se cuenta a si mismo.
```

`importar_lote.py` calcula lo mismo y lo muestra. **Borrar** pide los 8 primeros
caracteres de ese hash, y se compara contra el hash del **estado actual** del lote de esa
persona, no del ultimo zip: si se tomo una foto despues de exportar, el prefijo ya no vale y no se
pierde nada sin importar. Despues de borrar se comprueba que no quede ningun
archivo, y si queda alguno se dice cual. El zip que la hoja de compartir copia a
`cache/share_plus/` (Android) tambien se borra: lleva las fotos. Se descubrio probandolo en un
emulador.

## Red

La regla "sin red" se vigila de tres maneras, y ninguna es completa:

1. **Una prueba estatica** (`captura_pruebas_reglas_test`) con listas blancas de imports
   y palabras prohibidas: el codigo del modo no hace llamadas de red.
2. **El modelo de rostros va dentro de la app** (`blazeface.tfl` dentro del APK): no se
   descarga nada en ejecucion.
3. **El modo avion** durante la sesion, que es lo unico que lo garantiza de verdad.

**Por que no basta con las dos primeras:** ML Kit trae dentro `com.google.android.datatransport`
(sus POM `common`, `vision-common` y `face-detection` lo declaran), que es el transporte
con el que registra metricas de uso hacia Google. Por eso `INTERNET` aparece en el
manifiesto de las builds de release aunque nuestro codigo no lo pida. **No se ha
comprobado si en este build envia algo**; se comprueba con un proxy o el inspector de red
en el celular, que es lo que pide la spec. El manifiesto principal no se puede usar
para quitar `INTERNET` porque es el del producto real, que si necesita red.

**Riesgo aceptado (decision del responsable de la spec):** las sesiones de captura se hacen
en **modo avion** y por ahora **no se excluye `datatransport`**. Mientras no se mida el
trafico, el criterio de aceptacion 3 ("ninguna peticion de red") queda sin verificar, y
una sesion hecha con red puede mandar metricas de ML Kit a Google (nunca las fotos: no
pasan por ese transporte, pero eso tampoco esta medido).

## Cambios en `client/android/` y `client/ios/`

AGENTS.md pide avisar cuando se toca algo generado por `flutter create`. Se tocaron dos
archivos:

- `android/app/build.gradle.kts`: `minSdk = 26` en lugar de `flutter.minSdkVersion`, para
  que coincida con `docs/respuestas-claude-code.md`, C.20 (Android 8.0). Lo fija
  `captura_pruebas_reglas_test`.
- `android/app/src/main/AndroidManifest.xml`: se quitan `RECORD_AUDIO`,
  `WRITE_EXTERNAL_STORAGE` y `READ_EXTERNAL_STORAGE`. El plugin de camara declara los dos
  primeros aunque la app no graba audio ni escribe en almacenamiento compartido, y el
  fusionador agrega el tercero como "implicito". Quedan `CAMERA`, `INTERNET` y
  `ACCESS_NETWORK_STATE` (estos dos por bibliotecas, ver arriba).
- El mismo manifiesto declara `android:allowBackup="false"`. Sin eso, **por defecto Android
  sube los datos privados de la app a la cuenta de Google de la persona**, y ahi estan las
  fotos de rostros. La cuota de la copia automatica es de 25 MB por app, asi que un lote
  completo no cabria, pero uno parcial (unas ocho fotos) si. Afecta a toda la app, no solo
  a este modo: si el producto llegara a querer copia de seguridad, se haria con reglas que
  excluyan `captura_pruebas`, no quitando esta linea. Lo vigila `captura_pruebas_reglas_test`;
  la decision esta en [ADR 0021](../../../../docs/adr/0021-android-sin-copia-de-seguridad-automatica-en-toda-la-app.md).
- `ios/Runner/Info.plist`: `NSCameraUsageDescription`. Sin ella iOS cierra la app al abrir
  la camara.

**iOS no se ha compilado nunca** (no hay un Mac). Falta, al menos: ML Kit exige iOS 15.5
o mas y excluir `armv7` en el `Podfile`, que no esta en el repositorio porque Flutter lo
genera en la primera build de iOS. Hay que revisarlo cuando se compile en un Mac.

**iOS tampoco esta resuelto en copias de seguridad.** Lo que hay en `Documents` de una app
de iOS entra por defecto en las copias de iCloud y de iTunes. Excluir la carpeta
`captura_pruebas` pide codigo nativo (`NSURLIsExcludedFromBackupKey`) y no se ha hecho.
Hasta que se haga, no usar iOS para fotos reales de calibracion. **Pendiente** (anotado en el
ADR 0021).

## Compilar en una maquina con poca memoria

`android/gradle.properties` (la plantilla de Flutter) pide `-Xmx8G`. En un equipo con
8 GB o menos, la JVM de Gradle o el proceso de Dart mueren con "insufficient memory" /
"Out of memory" a mitad de una build (pasa a veces; reintentar o cerrar otras
aplicaciones). Para una build puntual se puede bajar el heap en ese archivo y restaurarlo
despues. No se cambio en el repositorio.

## Decisiones que la spec no fijaba

- `rostro.bbox` es `[izquierda, arriba, derecha, abajo]` en pixeles de la foto
  completa y orientada (el orden de `Rect`). La spec no dice el orden.
- La foto es **siempre JPEG** (`_foto.jpg`). El recorte solo decodifica JPEG, asi que el
  almacen, el esquema y los scripts rechazan `.heic`. En iOS la camara se fuerza a JPEG
  de forma explicita (`CameraPlatform.instance.setImageFileFormat`, que `camera` no
  expone en el controlador y por eso se importa `camera_platform_interface`); si aun asi
  llegara otro formato, la captura falla con un mensaje en lugar de guardar algo que no
  se puede recortar.
- `camara.parametros.exposicion` es el `ExposureTime` del EXIF, **en segundos**.
- `camara.espejo` (`true`, `false` o `null`) registra si la foto guardada esta reflejada
  en horizontal. La app **no la corrige**: la camara real hoy escribe `null` porque el
  plugin no lo informa (en iOS solo refleja la conexion del stream, no la foto, y en
  Android no hay nada que lo diga). Hay que mirar las fotos; `inspeccionar_lote.py` cuenta
  cuantas tomas dicen `true`, `false` y `null`.
- El JSON no guarda los controles de calidad del recorte ni `margenSuperiorPx`: se
  pueden recalcular desde la foto y el recorte.
- Una foto de un solo celular ocupa mas o menos 3 MB; un lote completo de un celular
  (6 personas x 15 tomas = 90) son unos 290 MB, y exportar un lote necesita su parte de
  espacio (unos 48 MB por persona).

## Lo que NO esta verificado

Todo esto necesita un telefono:

- Que el plugin de camara abra la frontal, pida el permiso y entregue un JPEG.
- Si la foto frontal sale en espejo (se registra en `camara.espejo`, no se corrige), y que
  su orientacion EXIF sea la esperada.
- Que en iOS la camara entregue JPEG con la peticion explicita.
- Que el EXIF traiga ISO, tiempo de exposicion y balance de blancos.
- Que ML Kit detecte bien en las copias reducidas, y la guia de distancia en vivo
  (rotacion de los fotogramas, rendimiento en gama baja).
- Que no salga ningun trafico de red (ver "Red").
- Que el zip se comparta por la hoja del sistema, y el espacio privado real de Android e iOS.
- Cualquier cosa de iOS.
