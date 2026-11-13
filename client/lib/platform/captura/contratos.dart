/// Contratos de la capa de captura.
///
/// Aqui no hay nada especifico de una plataforma a proposito: este archivo lo
/// importan tanto la rama movil como la de web. Las implementaciones viven en
/// `captura_movil.dart` y `captura_web.dart`, y `lib/platform/captura.dart`
/// elige una segun el target.
library;

import 'dart:typed_data';

import 'package:wearhack/core/atributos_c18.dart';
import 'package:wearhack/core/recorte/recortador_facial.dart';
import 'package:wearhack/core/vocabulario.dart';

export 'package:wearhack/core/recorte/recortador_facial.dart'
    show CajaRostro, RecorteFacial;

/// Lo que el pipeline on-device saca de la foto de una prenda.
///
/// Tipo, patron y textura van en el vocabulario de C.18 ([TipoC18] y compania),
/// que es el que valida el Closet del Core.
class PrendaClasificada {
  const PrendaClasificada({
    required this.imagenSinFondo,
    required this.tipo,
    required this.confianzaTipo,
    required this.patron,
    required this.confianzaPatron,
    required this.color,
    required this.categoriaColor,
    this.textura,
  });

  /// PNG con transparencia: la prenda ya recortada del fondo.
  final Uint8List imagenSinFondo;

  final TipoC18 tipo;
  final double confianzaTipo;
  final PatronC18 patron;
  final double confianzaPatron;

  /// `null` hasta que el usuario la elija en la revision (#55): no hay
  /// clasificador de textura, y el Closet pone la de por defecto del tipo.
  final TexturaC18? textura;

  final ColorLab color;

  /// TODO(#58): es la del vocabulario de las pantallas, no la de C.18. Hay que
  /// mapearla al subir (por ejemplo `marron` a `CAFE`) hasta que exista la
  /// tabla ISCC-NBS.
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

/// Detecta el rostro y lo recorta.
///
/// Para la colorimetria el backend recibe **solo el recorte**, nunca la foto
/// completa. Esa decision es de privacidad y de coste: una cara recortada son
/// unos pocos kilobytes, y el resto de la escena no aporta nada al calculo de
/// la temporada.
///
/// Esta es la **unica** funcion de recorte del cliente: el flujo real de
/// colorimetria y el modo de captura de pruebas la llaman, no hay copias. El
/// recorte sale en sRGB y sin perfil incrustado. No normaliza la iluminacion
/// ni reescala: eso esta por decidir con el protocolo de normalizacion.
abstract interface class FaceCropper {
  /// Recibe el JPEG original de la camara y devuelve el recorte, o `null` si
  /// no se ve un rostro usable.
  ///
  /// Un control de calidad que no se cumple no es `null`: queda en
  /// `RecorteFacial.controles`, y la app sugiere repetir sin obligar.
  ///
  /// Lanza `ConfiguracionRecorteInvalida` si faltan los margenes del recorte,
  /// `PerfilIccNoSoportado` si la foto trae un perfil que no se sabe leer, y
  /// `FormatException` si no es un JPEG.
  Future<RecorteFacial?> recortar(Uint8List foto);

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
