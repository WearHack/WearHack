# colorimetria

Calculo de la temporada de color del usuario.

El dispositivo detecta el rostro, lo recorta y lo normaliza, y sube **solo ese
recorte**. La foto completa nunca sale del telefono. Ver `FaceCropper`.

Solo movil: en web no hay camara ni ML Kit.

## La foto del rostro

`ui/pantalla_foto_rostro.dart` (issue #14). Reglas que cumple y que los tests
fijan (`test/foto_rostro_test.dart`):

- **No abre la camara sin consentimiento vigente.** Lo comprueba ella misma
  antes de crear la camara; no depende de que la pantalla anterior esconda el
  boton.
- **La foto completa solo llega a `FaceCropper`.** No hay plan B que la envie si
  el recorte falla (ADR 0016): sin rostro se pide repetir.
- **El recorte no se persiste.** Vive en memoria y sale por `Navigator.pop`. Los
  temporales del plugin de camara y del detector los borran sus implementaciones.
- Un control de calidad fallido sugiere repetir, pero nunca bloquea.

Pendiente: el envio del recorte al servicio, que espera al cliente HTTP, y medir
que envia la libreria `datatransport` de ML Kit (se hace con un telefono).
