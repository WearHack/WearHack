/// La camara, como una interfaz.
///
/// Las pantallas no conocen el plugin `camera`: hablan con esto. La
/// implementacion real vive en `lib/platform/captura_pruebas/` (movil) y en los
/// tests se usa una falsa. Asi la logica de las pantallas se prueba sin un
/// telefono.
library;

import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// Una foto recien tomada: los bytes del JPEG tal como los entrego la camara.
class FotoTomada {
  const FotoTomada({required this.bytes, required this.extension});

  final Uint8List bytes;

  /// `jpg` o `heic`, sin punto.
  final String extension;
}

/// El celular no tiene camara frontal.
class SinCamaraFrontal implements Exception {
  const SinCamaraFrontal();

  @override
  String toString() => 'SinCamaraFrontal: este celular no tiene camara frontal';
}

abstract interface class CamaraDeCaptura {
  /// Abre la camara frontal con el flash apagado. Puede lanzar
  /// [SinCamaraFrontal] o el error de permisos del sistema.
  Future<void> inicializar();

  /// La vista previa, para mostrar en pantalla. Solo valida despues de
  /// [inicializar].
  Widget vistaPrevia();

  /// Si la guia de distancia en vivo esta encendida. Esta apagada por defecto
  /// (`--dart-define=CAPTURA_GUIA_EN_VIVO=true` la enciende) porque pasar
  /// fotogramas a ML Kit con la rotacion correcta de cada sistema no se ha
  /// verificado en un telefono, y la captura de las 270 fotos no debe depender
  /// de algo sin probar. Apagada, la camara solo toma fotos.
  bool get guiaDeDistanciaActiva;

  /// Ancho del rostro detectado en vivo, en pixeles del fotograma de analisis, o
  /// `null` cuando no se ve ninguno. Alimenta la guia de distancia. Un fallo del
  /// detector no debe romper la captura: simplemente deja de emitir.
  Stream<int?> get anchoDelRostroEnVivo;

  /// Toma la foto a resolucion nativa. La implementacion debe **borrar el
  /// archivo temporal** que deje el plugin: la foto solo existe en los bytes.
  Future<FotoTomada> tomarFoto();

  /// Libera la camara. Se llama al salir de la pantalla.
  Future<void> liberar();
}
