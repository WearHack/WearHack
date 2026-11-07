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

## El analisis contra el Core

Con cuenta (Cognito configurado), el consentimiento y el analisis hablan con el
Core (`docs/api-usuarios.md`); sin cuenta siguen siendo los falsos.

- `conexion_core.dart`: URL base, token de acceso y errores, compartidos.
- `repositorio_consentimiento_core.dart`: el Core es la fuente de verdad del
  consentimiento. **Omitir no se envia**: no hay nada que autorizar, y solo se
  recuerda mientras la app siga abierta. La version del texto viaja como texto
  (`"1"`); una version que no sea un entero cuenta como desactualizada.
- `cliente_colorimetria.dart`: `POST /colorimetria` con el recorte PNG como
  cuerpo crudo (tope de 5 MiB en el Core), `GET` y `DELETE` del perfil.

Los errores se muestran como llegan. Un `422` (sin rostro, sin piel suficiente)
pide otra foto. Un `503` (servicio de IA caido) o la falta de red permiten
reintentar con el mismo recorte, que solo vive en memoria hasta que se analiza
o se sale de la pantalla: no se guarda.

Pendiente: medir que envia la libreria `datatransport` de ML Kit (se hace con un
telefono).
