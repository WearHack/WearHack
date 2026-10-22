# ADR 0021: Android sin copia de seguridad automatica en toda la app

- **Estado:** propuesto
- **Fecha:** 2026-10-14

## Contexto

Si el manifiesto no declara `android:allowBackup`, Android lo trata como `true` y sube los
datos privados de la app a la cuenta de Google de la persona. El modo de captura de
pruebas guarda ahi fotos de rostros de calibracion, que solo deben salir del telefono por
el lote exportado (ADR 0016 y la politica de datos de colorimetria).

## Decision

`client/android/app/src/main/AndroidManifest.xml` declara `android:allowBackup="false"`.
Afecta a **toda la app**, no solo al modo de captura: el atributo es de la aplicacion
entera. Un test (`captura_pruebas_reglas_test.dart`) lo fija para que nadie lo deshaga
sin darse cuenta.

Se descarto excluir solo la carpeta del modo con reglas de backup (`dataExtractionRules`):
es mas fino, pero hoy la app no tiene datos que merezca la pena respaldar, y una regla de
exclusion mal escrita falla en silencio.

## Consecuencias

Las fotos de calibracion no suben a Google. Se paga que una reinstalacion o un telefono
nuevo no restauran nada de la app; hoy no hay estado local que importe, y la fuente de la
verdad sera el servidor. Si el producto llegara a querer respaldo, se hara con reglas que
excluyan `captura_pruebas`, no quitando esta linea.

**Pendiente: iOS.** Lo que hay en `Documents` entra en las copias de iCloud y de iTunes y
excluirlo (`isExcludedFromBackup` sobre la carpeta `captura_pruebas`) pide codigo nativo
que no esta hecho. Hasta entonces no se usan iPhone con fotos reales de calibracion.

El manifiesto es un archivo generado por `flutter create` (AGENTS.md, "Donde no tocar"):
este cambio queda anotado aqui y debe sobrevivir a una regeneracion.
