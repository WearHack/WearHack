# closet

Digitalizar y consultar las prendas del usuario.

La clasificacion (quitar el fondo, color base, tipo, textura y patron) corre
**on-device**, no aqui: ver `lib/platform/captura/`. Esta capa solo orquesta
captura, muestra el resultado y lo sincroniza con el servicio `closet`.

En web esta funcion es de solo consulta: no hay camara ni interpretes.

## La cola de captura

`captura/cola_captura.dart` (issue #11). Es el motor: guarda las fotos, las procesa
por lotes y las sube con reintentos. `ui/pantalla_captura_prendas.dart` es la
pantalla: disparar solo encola, y desde ahi se ven los contadores de la cola, el
aviso de calor y las fallidas (reintentar o descartar).

| Pieza | Que hace |
|---|---|
| `ColaCaptura` | La cola. `encolar` solo guarda la foto y el indice; el trabajo corre aparte |
| `ProcesadorDePrendas` | Procesa un lote de fotos. `ProcesadorSobrePipeline` adapta el `GarmentPipeline` de hoy; #12 y #13 conectaran aqui su pipeline por etapas |
| `SubidorDePrendas` | Sube una prenda. Hoy es `SubidorPendiente`, que responde "sin red": las procesadas esperan en la cola sin perderse hasta que el Closet reciba prendas (#25) |
| `EstadoTermico` | Pausa el procesamiento si el telefono esta caliente. `EstadoTermicoDispositivo` (`captura/estado_termico.dart`) usa el estado termico del sistema en Android 10+ y la temperatura de la bateria en Android 8 y 9 |
| `CapturaDePrendas` | Cola, sensor y camara trasera ya conectados. Lo arma `abrirCapturaDePrendas()` en `platform/captura.dart` |
| `AlmacenCola` | Donde se guarda todo. `platform/captura/almacen_cola_archivos.dart` escribe en el directorio privado de la app |

Reglas que fijan los tests (`test/cola_captura_test.dart`):

- La foto se guarda **antes** que el indice; en la subida, el elemento sale del
  indice **antes** de borrar archivos. Asi una muerte en cualquier punto no pierde
  una foto.
- Solo se guardan estados estables (`porProcesar`, `porSubir`, `fallida`): lo que
  estaba a medias se repite al reabrir.
- La foto original se borra solo cuando el servidor confirma la subida.
- Sin red no cuenta como intento de la foto: se espera con retroceso exponencial
  (2 s, 4 s, 8 s... tope 5 min) y nunca la vuelve fallida.
- El `id` de cada foto es la **llave de idempotencia** de la subida.

## Encenderla

La captura esta **apagada por defecto** mientras falten el pipeline on-device (#12,
#13) y el endpoint del Closet (#25): sin ellos cada foto acabaria fallida o
esperando. Para probarla en un telefono:

```bash
flutter run --dart-define=CAPTURA_PRENDAS=true
```

Los umbrales de calor son provisionales (la spec no los fija): pausa desde el
estado `severo` del sistema, o desde 42 °C de bateria en Android 8 y 9. Se cambian
con `--dart-define=TERMICO_NIVEL_PAUSA=moderado` y
`--dart-define=TERMICO_BATERIA_MAX_C=40`.

No esta verificado sin un telefono: las metas de tiempo (siguiente foto p95 <= 1 s,
<= 2 s por prenda, primera prenda <= 5 s), la pausa por calor real, la camara
trasera y el directorio privado de la app.
