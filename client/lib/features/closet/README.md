# closet

Digitalizar y consultar las prendas del usuario.

La clasificacion (quitar el fondo, color base, tipo, textura y patron) corre
**on-device**, no aqui: ver `lib/platform/captura/`. Esta capa solo orquesta
captura, muestra el resultado y lo sincroniza con el servicio `closet`.

En web esta funcion es de solo consulta: no hay camara ni interpretes.
