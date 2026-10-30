/// La camara, como una interfaz.
///
/// Las pantallas no conocen el plugin `camera`: hablan con esto. La
/// implementacion real vive en `lib/platform/captura_pruebas/` (movil) y en los
/// tests se usa una falsa. Asi la logica de las pantallas se prueba sin un
/// telefono.
///
/// Esta interfaz la usan dos clientes: el modo de captura de pruebas y la foto
/// del rostro de la colorimetria (issue #14). Por eso vive aqui y no dentro de
/// `features/captura_pruebas/`: el producto no debe depender de una carpeta que
/// es una herramienta interna. No importa nada de plataforma, asi que la build
/// de web la compila sin problema.
library;

import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// Una foto recien tomada: los bytes del JPEG tal como los entrego la camara.
class FotoTomada {
  const FotoTomada({required this.bytes, required this.extension, this.espejo});

  final Uint8List bytes;

  /// Siempre `jpg`, sin punto: el recorte solo decodifica JPEG, asi que la
  /// camara real se niega a entregar otro formato.
  final String extension;

  /// Si la foto guardada esta reflejada en horizontal respecto a la escena (el
  /// efecto "selfie"), o `null` si no se sabe. Solo se **registra** en los
  /// metadatos: la app no la corrige.
  final bool? espejo;
}

/// El celular no tiene camara frontal.
class SinCamaraFrontal implements Exception {
  const SinCamaraFrontal();

  @override
  String toString() => 'SinCamaraFrontal: este celular no tiene camara frontal';
}

/// El celular no tiene camara trasera, la de las prendas.
class SinCamaraTrasera implements Exception {
  const SinCamaraTrasera();

  @override
  String toString() => 'SinCamaraTrasera: este celular no tiene camara trasera';
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
