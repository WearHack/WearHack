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
flutter run --dart-define=CAPTURA_PRUEBAS=true \
  --dart-define=RECORTE_MARGEN_SUPERIOR=... \
  --dart-define=RECORTE_MARGEN_INFERIOR=... \
  --dart-define=RECORTE_MARGEN_LATERAL=...
```

| Define | Para que | Sin el |
|---|---|---|
| `CAPTURA_PRUEBAS=true` | Enciende el modo y el boton que lo abre | El modo no existe |
| `RECORTE_MARGEN_SUPERIOR`, `_INFERIOR`, `_LATERAL` | Margenes del recorte, como fraccion del recuadro del rostro. **No tienen valor por defecto**: no estan definidos | El recorte falla nombrando los que faltan |
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
  exportaciones/    lote_<8 caracteres>.zip
```

Una toma "existe" cuando existe su `.json`. La foto **no se recodifica**: asi
conserva su perfil de color (ver `lib/core/color/`).

## Exportar y borrar

El zip es **plano** (sin carpetas) y trae `manifiesto.json`. El hash global es:

```
SHA-256 del texto formado por una linea  "<sha256>  <nombre>\n"  por archivo
(dos espacios, como sha256sum), ordenadas por nombre en orden ordinal.
El manifiesto no se cuenta a si mismo.
```

`importar_lote.py` calcula lo mismo y lo muestra. **Borrar** pide los 8 primeros
caracteres de ese hash, y se compara contra el hash del **estado actual**, no del
ultimo zip: si se tomo una foto despues de exportar, el prefijo ya no vale y no se
pierde nada sin importar. Despues de borrar se comprueba que no quede ningun
archivo, y si queda alguno se dice cual.

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

## Cambios en `client/android/` y `client/ios/`

AGENTS.md pide avisar cuando se toca algo generado por `flutter create`. Se tocaron dos
archivos:

- `android/app/src/main/AndroidManifest.xml`: se quitan `RECORD_AUDIO`,
  `WRITE_EXTERNAL_STORAGE` y `READ_EXTERNAL_STORAGE`. El plugin de camara declara los dos
  primeros aunque la app no graba audio ni escribe en almacenamiento compartido, y el
  fusionador agrega el tercero como "implicito". Quedan `CAMERA`, `INTERNET` y
  `ACCESS_NETWORK_STATE` (estos dos por bibliotecas, ver arriba).
- `ios/Runner/Info.plist`: `NSCameraUsageDescription`. Sin ella iOS cierra la app al abrir
  la camara.

**iOS no se ha compilado nunca** (no hay un Mac). Falta, al menos: ML Kit exige iOS 15.5
o mas y excluir `armv7` en el `Podfile`, que no esta en el repositorio porque Flutter lo
genera en la primera build de iOS. Hay que revisarlo cuando se compile en un Mac.

## Compilar en una maquina con poca memoria

`android/gradle.properties` (la plantilla de Flutter) pide `-Xmx8G`. En un equipo con
8 GB o menos, la JVM de Gradle o el proceso de Dart mueren con "insufficient memory" /
"Out of memory" a mitad de una build (pasa a veces; reintentar o cerrar otras
aplicaciones). Para una build puntual se puede bajar el heap en ese archivo y restaurarlo
despues. No se cambio en el repositorio.

## Decisiones que la spec no fijaba

- `rostro.bbox` es `[izquierda, arriba, derecha, abajo]` en pixeles de la foto
  completa y orientada (el orden de `Rect`). La spec no dice el orden.
- La extension de la foto puede ser `jpg` o `heic`.
- El JSON no guarda los controles de calidad del recorte ni `margenSuperiorPx`: se
  pueden recalcular desde la foto y el recorte.
- Una foto de un solo celular ocupa mas o menos 3 MB; un lote completo de un celular
  (6 personas x 15 tomas) son unos 290 MB, y exportar necesita otro tanto de espacio.

## Lo que NO esta verificado

Todo esto necesita un telefono:

- Que el plugin de camara abra la frontal, pida el permiso y entregue un JPEG.
- Que la foto frontal no salga en espejo, y que su orientacion EXIF sea la esperada.
- Que el EXIF traiga ISO, tiempo de exposicion y balance de blancos.
- Que ML Kit detecte bien en las copias reducidas, y la guia de distancia en vivo
  (rotacion de los fotogramas, rendimiento en gama baja).
- Que no salga ningun trafico de red (ver "Red").
- Que el zip se comparta por la hoja del sistema, y el espacio privado real de Android e iOS.
- Cualquier cosa de iOS.
