# ADR 0018: Validacion de segmentacion facial con MediaPipe y licencia de EasyPortrait

- **Estado:** aceptado
- **Fecha:** 2026-10-29

## Contexto

Para evaluar mejoras en el recorte facial on-device se reviso `license/en_us.pdf`
de EasyPortrait (variante CC BY-SA 4.0). La revision confirma que la
segmentacion contempla cabello, que es un requisito para pruebas de colorimetria.

La epica de referencia es WearHack/WearHack#63 y la brecha de licencia asociada
esta en la seccion 4 del registro interno de brechas.

## Decision

Se habilita la validacion de segmentacion facial con MediaPipe comparada contra
EasyPortrait, con estas restricciones:

1. **Solo validacion** de calidad de segmentacion y cobertura de cabello.
2. **Sin entrenamiento ni fine-tuning** de modelos de EasyPortrait.
3. Evidencia legal y tecnica guardada en la **boveda** del proyecto.

## Consecuencias

Se reduce el riesgo legal al dejar explicito el alcance permitido de uso y al no
abrir un flujo de entrenamiento con activos de terceros.

La implementacion funcional puede avanzar sin bloquear ADR 0016: solo cambia el
criterio de validacion del recorte, no la regla de privacidad de que solo sale
del dispositivo el recorte facial.
