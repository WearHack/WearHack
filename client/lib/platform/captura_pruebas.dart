/// Punto de entrada unico al modo de captura de pruebas.
///
/// Igual que `captura.dart`: el import condicional decide la implementacion.
///
/// - con `dart:io` (Android, iOS) entra `captura_pruebas_movil.dart`
/// - en cualquier otro caso (web) entra `captura_pruebas_web.dart`
///
/// Por defecto se elige la de web, para que un target nuevo falle en la captura
/// y no en toda la build.
library;

export 'captura_pruebas/captura_pruebas_web.dart'
    if (dart.library.io) 'captura_pruebas/captura_pruebas_movil.dart';
