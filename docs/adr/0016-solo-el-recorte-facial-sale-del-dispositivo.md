# ADR 0016: Para la colorimetria solo sale del dispositivo el recorte facial

- **Estado:** aceptado
- **Fecha:** 2026-09-22

## Contexto

Calcular la temporada de color necesita la piel del usuario. A diferencia de las
prendas ([ADR 0002](0002-clasificacion-de-prendas-on-device.md)), esta parte si
corre en el backend, por nearest-centroid sobre centroides que se recalibran de
noche.

## Decision

El dispositivo detecta el rostro con ML Kit, lo recorta y lo normaliza, y sube
**solo ese recorte**. La foto completa nunca sale del telefono.

El servicio `colorimetria` recibe la clave del recorte en el object storage, no
la imagen y no la foto original.

## Consecuencias

Es lo correcto por privacidad y ademas sale mas barato: una cara recortada y
normalizada son unos pocos kilobytes, y el resto de la escena no aporta nada al
calculo.

Si el recorte falla en el dispositivo, no hay plan B en el servidor. Eso es
intencionado: un plan B en el servidor significaria subir la foto completa.

El bucket `wearhack-rostros` guarda datos biometricos. Es privado, se sirve con
URLs firmadas de duracion corta, y merece su propia politica de retencion. Esa
politica esta pendiente.

La normalizacion de iluminacion la hace el dispositivo. Si dos telefonos
normalizan distinto, la temporada sale distinta, y eso se vera como ruido en los
centroides de [ADR 0011](0011-jobs-batch-como-tareas-programadas-de-ecs.md).
