/// Contratos de la capa de captura.
///
/// Aqui no hay nada especifico de una plataforma a proposito: este archivo lo
/// importan tanto la rama movil como la de web. Las implementaciones viven en
/// `captura_movil.dart` y `captura_web.dart`, y `lib/platform/captura.dart`
/// elige una segun el target.
library;

import 'dart:typed_data';

import 'package:wearhack/core/vocabulario.dart';

/// Lo que el pipeline on-device saca de la foto de una prenda.
class PrendaClasificada {
  const PrendaClasificada({
    required this.imagenSinFondo,
    required this.tipo,
    required this.textura,
    required this.patron,
    required this.color,
    required this.categoriaColor,
  });

  /// PNG con transparencia: la prenda ya recortada del fondo.
  final Uint8List imagenSinFondo;

  final TipoPrenda tipo;
  final Textura textura;
  final Patron patron;
  final ColorLab color;
  final CategoriaColor categoriaColor;
}

/// Clasifica una prenda sin salir del dispositivo.
///
/// No existe un servicio backend equivalente. La foto original no se sube:
/// solo viaja `imagenSinFondo` junto con los atributos.
///
/// **Los interpretes se cargan de uno en uno.** u2netp y el clasificador juntos
/// en memoria sacan del proceso a los telefonos con poca RAM, que son justo los
/// que hay que soportar. Por eso [procesar] carga, usa y libera cada modelo por
/// turnos en vez de tenerlos los dos listos.
abstract interface class GarmentPipeline {
  /// Reserva lo que haga falta antes del primer uso.
  Future<void> preparar();

  /// Quita el fondo y deduce tipo, textura, patron y color.
  Future<PrendaClasificada> procesar(Uint8List foto);

  /// Suelta interpretes y memoria. Llamarlo al salir de la captura.
  Future<void> liberar();

  /// Si esta plataforma puede ejecutar el pipeline.
  ///
  /// En web es `false`: la UI tiene que ocultar la captura en vez de dejar que
  /// falle al pulsarla.
  bool get disponible;
}

/// Detecta el rostro, lo recorta y lo normaliza.
///
/// Para la colorimetria el backend recibe **solo el recorte**, nunca la foto
/// completa. Esa decision es de privacidad y de coste: una cara recortada y
/// normalizada son unos pocos kilobytes, y el resto de la escena no aporta
/// nada al calculo de la temporada.
abstract interface class FaceCropper {
  /// Devuelve el recorte normalizado, o `null` si no se ve una cara usable.
  Future<Uint8List?> recortar(Uint8List foto);

  bool get disponible;
}

/// La plataforma actual no puede hacer esto.
///
/// Es distinto de un fallo: en web se espera y la UI debe consultar
/// `disponible` antes de llegar aqui.
class CapturaNoDisponible implements Exception {
  const CapturaNoDisponible(this.detalle);
  final String detalle;

  @override
  String toString() => 'CapturaNoDisponible: $detalle';
}
