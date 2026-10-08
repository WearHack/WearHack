/// El recorte facial del producto: de la foto completa al PNG que viaja.
///
/// Es la **unica** funcion de recorte del cliente. El flujo real de
/// colorimetria y el modo de captura de pruebas llaman a esta misma clase, no a
/// copias: lo que se calibra es lo que el producto hara.
///
/// Pasos, en este orden:
///
/// 1. Leer el perfil ICC del JPEG original, sin recodificarlo.
/// 2. Decodificar. La libreria aplica la orientacion EXIF al decodificar, asi
///    que las coordenadas del detector y del recorte hablan del mismo espacio.
/// 3. Dar al detector una copia reducida (detectar no necesita 12 megapixeles).
/// 4. Quedarse con el rostro mas grande y llevarlo a la foto completa.
/// 5. Recortar sobre la foto completa, con los margenes configurados.
/// 6. Convertir el recorte a sRGB. **El perfil no sobrevive** a ninguna ruta de
///    recodificacion de Dart (ver `lib/core/color/perfil_icc.dart`), asi que el
///    PNG sale con los pixeles ya en sRGB y sin perfil incrustado.
/// 7. Medir los controles de calidad y codificar a PNG.
///
/// No se normaliza la iluminacion ni se reescala: la correccion del color de la
/// luz esta por decidir con el protocolo, y alterar pixeles aqui contaminaria
/// esa medicion. Tampoco se rota para alinear los ojos, por lo mismo.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:wearhack/core/color/conversion.dart';
import 'package:wearhack/core/color/jpeg_icc.dart';
import 'package:wearhack/core/color/perfil_icc.dart';
import 'package:wearhack/core/recorte/configuracion_recorte.dart';
import 'package:wearhack/core/recorte/controles_calidad.dart';

/// Lo que dice `RecorteFacial.perfilRecorte`: el recorte siempre sale en sRGB.
const String perfilDelRecorte = 'sRGB (convertido por la app)';

/// Recuadro de un rostro, en pixeles de la imagen que se le dio al detector.
class CajaRostro {
  const CajaRostro({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  double get area => width * height;

  bool get esUsable =>
      left.isFinite &&
      top.isFinite &&
      width.isFinite &&
      height.isFinite &&
      width > 0 &&
      height > 0;

  CajaRostro escalada(double factor) => CajaRostro(
    left: left * factor,
    top: top * factor,
    width: width * factor,
    height: height * factor,
  );

  @override
  String toString() => 'CajaRostro($left, $top, $width x $height)';
}

/// Detecta rostros. En el telefono lo hace ML Kit; en los tests, un doble.
abstract interface class DetectorRostro {
  /// Recibe un JPEG ya **vertical** (sin orientacion EXIF pendiente) y
  /// devuelve los recuadros en los pixeles de ese JPEG.
  Future<List<CajaRostro>> detectar(Uint8List jpegVertical);
}

/// Ejecuta una tarea pesada. Por defecto en el mismo isolate; en el telefono,
/// en uno aparte para no congelar la interfaz mientras se decodifican
/// 12 megapixeles.
typedef Ejecutor = Future<R> Function<R>(FutureOr<R> Function() tarea);

Future<R> ejecutarEnElMismoIsolate<R>(FutureOr<R> Function() tarea) async =>
    await tarea();

/// La foto ya decodificada y orientada, lista para detectar y recortar.
///
/// Solo lleva tipos que se pueden enviar entre isolates: los perfiles ICC
/// viajan como bytes porque sus curvas son funciones.
class FotoPreparada {
  const FotoPreparada({
    required this.pixeles,
    required this.ancho,
    required this.alto,
    required this.jpegDeteccion,
    required this.escala,
    required this.perfilBytes,
    required this.descripcionPerfil,
  });

  /// RGB empaquetado (3 bytes por pixel) de la foto completa y orientada, en el
  /// espacio de color de [perfilBytes].
  final Uint8List pixeles;
  final int ancho;
  final int alto;

  /// Copia reducida y vertical para el detector.
  final Uint8List jpegDeteccion;

  /// Cuanto hay que multiplicar un recuadro de [jpegDeteccion] para llevarlo a
  /// la foto completa.
  final double escala;

  /// Perfil ICC del JPEG original, o `null` si no traia.
  final Uint8List? perfilBytes;

  /// Nombre del perfil, para el JSON de metadatos.
  final String descripcionPerfil;

  /// Cuando no hay perfil se asume sRGB. Es una apuesta, y queda anotada.
  bool get perfilSupuesto => perfilBytes == null;
}

/// El resultado de un recorte.
class RecorteFacial {
  const RecorteFacial({
    required this.png,
    required this.ancho,
    required this.alto,
    required this.caja,
    required this.margenSuperiorPx,
    required this.perfilOrigen,
    required this.perfilOrigenSupuesto,
    required this.variosRostros,
    required this.controles,
  });

  /// El PNG que se guarda o se envia, en sRGB y sin perfil incrustado.
  final Uint8List png;
  final int ancho;
  final int alto;

  /// El rostro, en pixeles de la foto completa y orientada.
  final CajaRostro caja;

  /// Pixeles de margen que quedaron sobre el rostro. Puede ser menor que el
  /// pedido si el rostro estaba pegado al borde de la foto: es la senal para
  /// distinguir un recorte sin espacio para el cabello de una ausencia real.
  final int margenSuperiorPx;

  /// Nombre del perfil de la foto original.
  final String perfilOrigen;

  /// `true` si la foto no traia perfil y se asumio sRGB.
  final bool perfilOrigenSupuesto;

  /// Siempre [perfilDelRecorte].
  String get perfilRecorte => perfilDelRecorte;

  /// Habia mas de un rostro; se uso el mas grande.
  final bool variosRostros;

  final ControlesCalidad controles;

  int get anchoRostroPx => caja.width.round();
}

/// Decodifica, orienta y reduce la foto. Trabajo pesado y sin plataforma.
///
/// Lanza [FormatException] si no es un JPEG decodificable y
/// [PerfilIccNoSoportado] si trae un perfil que no se sabe interpretar: el
/// servidor nunca debe recibir colores sin saber en que espacio estan.
FotoPreparada prepararFoto(Uint8List foto, {required int ladoMaximoDeteccion}) {
  final Uint8List? perfilBytes = extraerIccDeJpeg(foto);
  final String descripcion = perfilBytes == null
      ? 'sin perfil (se asume sRGB)'
      : (PerfilRgb.desdeBytes(perfilBytes).descripcion ??
            'perfil ICC sin nombre');

  final img.Image? decodificada = img.decodeJpg(foto);
  if (decodificada == null) {
    throw const FormatException('No se pudo decodificar el JPEG');
  }
  final img.Image enRgb = decodificada.numChannels == 3
      ? decodificada
      : decodificada.convert(numChannels: 3);
  // `decodeJpg` ya aplica la orientacion EXIF (verificado en image 4.10.1: con
  // orientacion 6 u 8 devuelve las dimensiones intercambiadas y borra la
  // etiqueta). No se vuelve a aplicar, pero `recortador_facial_test.dart` fija
  // ese comportamiento para las 8 orientaciones: si una version nueva de la
  // libreria dejara de hacerlo, el recorte saldria girado y ese test falla.
  final img.Image vertical = enRgb;

  final int ancho = vertical.width;
  final int alto = vertical.height;
  final Uint8List pixeles = Uint8List.fromList(
    vertical.getBytes(order: img.ChannelOrder.rgb),
  );
  if (pixeles.length != ancho * alto * 3) {
    throw StateError('Los pixeles no estan empaquetados como RGB');
  }

  final int ladoMayor = ancho > alto ? ancho : alto;
  final img.Image paraDetectar = ladoMayor > ladoMaximoDeteccion
      ? img.copyResize(
          vertical,
          width: (ancho * ladoMaximoDeteccion / ladoMayor).round(),
          height: (alto * ladoMaximoDeteccion / ladoMayor).round(),
          interpolation: img.Interpolation.linear,
        )
      : vertical;
  // El perfil que `image` decodifica viene con 2 bytes de mas, y lo que importa
  // aqui es la geometria: la copia del detector no lleva perfil ni EXIF.
  paraDetectar
    ..iccProfile = null
    ..exif = img.ExifData();

  return FotoPreparada(
    pixeles: pixeles,
    ancho: ancho,
    alto: alto,
    jpegDeteccion: img.encodeJpg(paraDetectar, quality: 90),
    escala: ancho / paraDetectar.width,
    perfilBytes: perfilBytes,
    descripcionPerfil: descripcion,
  );
}

/// Recorta [caja] (en pixeles de la foto completa), convierte a sRGB, mide la
/// calidad y codifica a PNG. Devuelve `null` si el recorte queda vacio.
RecorteFacial? recortarYConvertir(
  FotoPreparada foto,
  CajaRostro caja,
  ConfiguracionRecorte configuracion, {
  required bool variosRostros,
}) {
  final double margenX = caja.width * configuracion.margenLateral;
  final double margenArriba = caja.height * configuracion.margenSuperior;
  final double margenAbajo = caja.height * configuracion.margenInferior;

  final int x0 = (caja.left - margenX).floor().clamp(0, foto.ancho);
  final int y0 = (caja.top - margenArriba).floor().clamp(0, foto.alto);
  final int x1 = (caja.right + margenX).ceil().clamp(0, foto.ancho);
  final int y1 = (caja.bottom + margenAbajo).ceil().clamp(0, foto.alto);
  final int ancho = x1 - x0;
  final int alto = y1 - y0;
  if (ancho < 1 || alto < 1) return null;

  final Uint8List recorte = Uint8List(ancho * alto * 3);
  for (int y = 0; y < alto; y++) {
    final int desde = ((y0 + y) * foto.ancho + x0) * 3;
    recorte.setRange(y * ancho * 3, (y + 1) * ancho * 3, foto.pixeles, desde);
  }

  // Sin perfil se asume sRGB y no se toca ningun byte.
  if (foto.perfilBytes != null) {
    ConversorASrgb(PerfilRgb.desdeBytes(foto.perfilBytes!))
        .convertirEnSitio(recorte);
  }

  final ControlesCalidad controles = medirCalidad(
    recorte,
    ancho: ancho,
    alto: alto,
    anchoRostroPx: caja.width.round(),
    configuracion: configuracion,
  );

  final img.Image imagen = img.Image.fromBytes(
    width: ancho,
    height: alto,
    bytes: recorte.buffer,
    numChannels: 3,
  );

  return RecorteFacial(
    png: Uint8List.fromList(img.encodePng(imagen)),
    ancho: ancho,
    alto: alto,
    caja: caja,
    margenSuperiorPx: (caja.top - y0).round().clamp(0, foto.alto),
    perfilOrigen: foto.descripcionPerfil,
    perfilOrigenSupuesto: foto.perfilSupuesto,
    variosRostros: variosRostros,
    controles: controles,
  );
}

class RecortadorFacial {
  const RecortadorFacial({
    required this.detector,
    required this.configuracion,
    this.ejecutor = ejecutarEnElMismoIsolate,
  });

  final DetectorRostro detector;
  final ConfiguracionRecorte configuracion;
  final Ejecutor ejecutor;

  /// Devuelve `null` si no se ve un rostro usable. Un control de calidad que no
  /// se cumple no devuelve `null`: queda en `controles.fallidos`.
  Future<RecorteFacial?> recortar(Uint8List foto) async {
    final ConfiguracionRecorte c = configuracion;
    final FotoPreparada preparada = await ejecutor(
      () => prepararFoto(foto, ladoMaximoDeteccion: c.ladoMaximoDeteccion),
    );

    final List<CajaRostro> cajas = <CajaRostro>[
      for (final CajaRostro caja in await detector.detectar(
        preparada.jpegDeteccion,
      ))
        if (caja.esUsable) caja,
    ];
    if (cajas.isEmpty) return null;

    final CajaRostro mayor = cajas.reduce(
      (CajaRostro a, CajaRostro b) => a.area >= b.area ? a : b,
    );
    final CajaRostro enLaFoto = mayor.escalada(preparada.escala);
    final bool varios = cajas.length > 1;

    return ejecutor(
      () => recortarYConvertir(preparada, enLaFoto, c, variosRostros: varios),
    );
  }
}
