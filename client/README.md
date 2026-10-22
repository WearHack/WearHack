# Cliente WearHack

Un solo proyecto Flutter para Android, iOS y Web. La prioridad es movil.

## Arrancar

```bash
flutter pub get
flutter run --dart-define=API_BASE=http://10.0.2.2:8080
```

`10.0.2.2` es como el emulador de Android ve el equipo anfitrion, donde corre el
gateway del `docker compose`. En un dispositivo fisico hay que poner la IP de la
maquina en la red local.

## Lo que hace el dispositivo y lo que hace el backend

La clasificacion de prendas corre **aqui**, no en el servidor. Quitar el fondo y
deducir tipo, textura y patron pasa en el telefono con LiteRT/TFLite. No existe
un servicio backend de clasificacion, y la foto original nunca se sube: solo
viaja la imagen ya procesada.

Para la colorimetria el dispositivo detecta el rostro, lo recorta y lo
normaliza, y manda **solo ese recorte**. La foto completa no sale del telefono.

## Web es otra cosa

En web WearHack es solo consulta y gestion. No hay camara ni interpretes, y no
es algo temporal: ejecutar los modelos en una pestana significaria bajar decenas
de megabytes y correrlos con mucho menos acelerador que en el movil.

Todo el codigo de captura vive detras de `lib/platform/captura.dart`, que elige
implementacion con un import condicional. La rama de movil depende de `dart:io`,
que en web no existe, asi que **un import mal aislado rompe `flutter build web`**
y en ningun otro sitio. Esa build en CI es la red de seguridad de esta frontera.

## Estructura

| Ruta | Que hay |
|---|---|
| `lib/app/` | Navegacion principal: closet, outfits y semana |
| `lib/core/` | Vocabulario compartido con el backend y configuracion |
| `lib/core/ui/` | Textos, iconos y colores del vocabulario, y estados vacio y error |
| `lib/features/` | Closet, outfits y colorimetria |
| `lib/mock/` | Repositorio falso en memoria. Las pantallas lo usan hasta que exista el cliente HTTP |
| `lib/platform/captura/` | Pipeline on-device y recorte de rostro |
| `assets/models/` | Vacia en git. Ver su README |

## Comandos

```bash
dart format lib test
```

```bash
flutter analyze
```

```bash
flutter test
```

```bash
flutter build apk --debug
```

```bash
flutter build web
```
