# Modelos on-device

Esta carpeta va vacia en git. Los modelos pesan decenas de megabytes y no tienen
por que vivir en el historial.

La clasificacion de prendas corre **en el dispositivo**, no en el backend. No
existe ni va a existir un servicio de clasificacion: la foto de una prenda no
sale del telefono, y solo se sube la imagen ya procesada.

## Que va aqui

| Archivo | Para que | Notas |
|---|---|---|
| `u2netp.tflite` | Quitar el fondo de la prenda | Version ligera de U^2-Net |
| `clasificador_prenda.tflite` | Tipo, textura y patron | MobileNetV3-Small multi-head, cuantizado a INT8 |

La deteccion y el recorte de rostro no llevan modelo propio: los hace ML Kit,
que trae el suyo dentro del paquete.

## Por que INT8 y por que multi-head

El objetivo es gama media-baja. INT8 reduce el modelo a la cuarta parte y corre
en el acelerador del telefono; en float32 muchos dispositivos caen a CPU. Y un
solo modelo con tres cabezas en vez de tres modelos separados significa una
carga de pesos en vez de tres.

## Carga secuencial

Los interpretes se cargan y se liberan **de uno en uno**, nunca a la vez.
u2netp y el clasificador juntos en memoria sacan del proceso a los telefonos
con poca RAM, que son justo los que hay que soportar. Ver `GarmentPipeline`.

## De donde salen

Pendiente: aun no hay pipeline de entrenamiento ni artefactos publicados. Cuando
lo haya, aqui va el enlace y como verificar el hash.
