/// Punto de entrada unico a la ubicacion del dispositivo.
///
/// Mismo patron que `captura.dart`: el import condicional elige la
/// implementacion. La de web usa `dart:js_interop`, que fuera del navegador no
/// existe, y por defecto entra la que no hace nada. Asi un target nuevo pierde
/// la ubicacion, no la build.
library;

export 'ubicacion/contratos.dart';
export 'ubicacion/ubicacion_otras.dart'
    if (dart.library.js_interop) 'ubicacion/ubicacion_web.dart';
