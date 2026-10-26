# closet

Digitalizar y consultar las prendas del usuario.

La clasificacion (quitar el fondo, color base, tipo, textura y patron) corre
**on-device**, no aqui: ver `lib/platform/captura/`. Esta capa solo orquesta
captura, muestra el resultado y lo sincroniza con el servicio `closet`.

En web esta funcion es de solo consulta: no hay camara ni interpretes.

## La cola de captura

`captura/cola_captura.dart` (issue #11). Es el motor, sin pantalla todavia: guarda
las fotos, las procesa por lotes y las sube con reintentos.

| Pieza | Que hace |
|---|---|
| `ColaCaptura` | La cola. `encolar` solo guarda la foto y el indice; el trabajo corre aparte |
| `ProcesadorDePrendas` | Procesa un lote de fotos. `ProcesadorSobrePipeline` adapta el `GarmentPipeline` de hoy; #12 y #13 conectaran aqui su pipeline por etapas |
| `SubidorDePrendas` | Sube una prenda. Sin implementacion real hasta que exista el cliente HTTP |
| `EstadoTermico` | Pausa el procesamiento si el telefono esta caliente. Sin sensor real todavia |
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

No esta verificado sin un telefono: las metas de tiempo (siguiente foto p95 <= 1 s,
<= 2 s por prenda, primera prenda <= 5 s), la pausa por calor real y el
directorio privado de la app.
