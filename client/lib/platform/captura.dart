/// Punto de entrada unico a la capa de captura.
///
/// El resto de la aplicacion importa SOLO este archivo. El import condicional
/// decide cual de las dos implementaciones entra en la build:
///
/// - con `dart:io` disponible (Android, iOS) entra `captura_movil.dart`
/// - en cualquier otro caso (web) entra `captura_web.dart`
///
/// La rama de web se elige por defecto, no la de movil. Asi, si algun dia se
/// compila para un target nuevo, lo que falla es la captura y no la build
/// entera.
library;

export 'captura/contratos.dart';
export 'captura/captura_web.dart'
    if (dart.library.io) 'captura/captura_movil.dart';
