/// Lo que rodea a u2netp (issue #12) y no depende de LiteRT: preparar la
/// entrada, convertir la mascara en transparencia y recortar la prenda.
///
/// El modelo son los pesos oficiales de u2netp exportados con
/// `tools/entrenamiento/fondo/exportar.py`: entrada `(1, 320, 320, 3)` RGB en
/// `[0, 255]` (la normalizacion va dentro) y salida `(1, 320, 320, 1)`, la
/// probabilidad de que cada pixel sea primer plano.
///
/// Solo Dart, sin plugins: corre igual en el telefono y en las pruebas.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Lado de la entrada y de la salida de u2netp.
const int ladoEntradaRemovedor = 320;

/// Alfa a partir del cual un pixel cuenta como prenda para el recorte. Es el
/// mismo umbral por defecto que usa el color base (`alfaMinimo`).
const int alfaMinimoRecorte = 128;

/// La entrada de u2netp: la foto entera escalada a 320 x 320 sin conservar la
/// proporcion, como en el preproceso oficial, en RGB float32 `[0, 255]`.
Float32List entradaDelRemovedor(img.Image foto) {
  if (foto.width == 0 || foto.height == 0) {
    throw ArgumentError('La foto esta vacia');
  }
  final img.Image escalada = img.copyResize(
    foto,
    width: ladoEntradaRemovedor,
    height: ladoEntradaRemovedor,
    interpolation: img.Interpolation.linear,
  );
  final Float32List entrada = Float32List(
    ladoEntradaRemovedor * ladoEntradaRemovedor * 3,
  );
  int i = 0;
  for (int y = 0; y < ladoEntradaRemovedor; y++) {
    for (int x = 0; x < ladoEntradaRemovedor; x++) {
      final img.Pixel p = escalada.getPixel(x, y);
      entrada[i++] = p.r.toDouble();
      entrada[i++] = p.g.toDouble();
      entrada[i++] = p.b.toDouble();
    }
  }
  return entrada;
}

/// Aplica la mascara de u2netp a la foto: la mascara se normaliza a `[0, 1]`
/// con su minimo y su maximo (como en el codigo oficial), se escala al tamano
/// de la foto y pasa a ser el canal alfa. Luego se recorta a la caja de los
/// pixeles con alfa >= [alfaMinimoRecorte], porque el clasificador se entreno
/// con prendas recortadas.
///
/// Si no queda ningun pixel por encima del umbral, devuelve la foto entera
/// transparente: el pipeline lo convierte en `PrendaSinPixeles`.
img.Image aplicarMascara(img.Image foto, Float32List mascara) {
  const int n = ladoEntradaRemovedor * ladoEntradaRemovedor;
  if (mascara.length != n) {
    throw FormatException(
      'La mascara tiene ${mascara.length} valores; se esperaban $n',
    );
  }
  double minimo = double.infinity;
  double maximo = double.negativeInfinity;
  for (final double v in mascara) {
    minimo = math.min(minimo, v);
    maximo = math.max(maximo, v);
  }
  final double rango = maximo - minimo;

  final img.Image pequena = img.Image(
    width: ladoEntradaRemovedor,
    height: ladoEntradaRemovedor,
    numChannels: 1,
  );
  for (int i = 0; i < n; i++) {
    // Mascara plana: no hay nada que distinguir, todo es fondo.
    final double v = rango < 1e-6 ? 0 : (mascara[i] - minimo) / rango;
    pequena.setPixelR(
      i % ladoEntradaRemovedor,
      i ~/ ladoEntradaRemovedor,
      (v * 255).round(),
    );
  }
  final img.Image alfa = img.copyResize(
    pequena,
    width: foto.width,
    height: foto.height,
    interpolation: img.Interpolation.linear,
  );

  final img.Image rgba = img.Image(
    width: foto.width,
    height: foto.height,
    numChannels: 4,
  );
  int x0 = foto.width, y0 = foto.height, x1 = -1, y1 = -1;
  for (int y = 0; y < foto.height; y++) {
    for (int x = 0; x < foto.width; x++) {
      final img.Pixel p = foto.getPixel(x, y);
      final int a = alfa.getPixel(x, y).r.toInt();
      rgba.setPixelRgba(x, y, p.r, p.g, p.b, a);
      if (a >= alfaMinimoRecorte) {
        x0 = math.min(x0, x);
        y0 = math.min(y0, y);
        x1 = math.max(x1, x);
        y1 = math.max(y1, y);
      }
    }
  }
  if (x1 < 0) {
    // Nada por encima del umbral: todo transparente.
    img.fill(rgba, color: img.ColorRgba8(0, 0, 0, 0));
    return rgba;
  }
  return img.copyCrop(
    rgba,
    x: x0,
    y: y0,
    width: x1 - x0 + 1,
    height: y1 - y0 + 1,
  );
}

/// Todo el paso de quitar el fondo, con la inferencia inyectada: decodifica el
/// JPEG (que ya aplica la orientacion EXIF), prepara la entrada, llama a
/// [inferir] y aplica la mascara. La rama movil lo corre en un isolate con
/// LiteRT; las pruebas, con una mascara falsa.
img.Image quitarFondoConMascara(
  Uint8List jpeg,
  Float32List Function(Float32List entrada) inferir,
) {
  img.Image? decodificada;
  try {
    decodificada = img.decodeJpg(jpeg);
  } on img.ImageException {
    decodificada = null;
  }
  if (decodificada == null) {
    throw const FormatException('No se pudo decodificar el JPEG');
  }
  final img.Image foto = decodificada.numChannels == 3
      ? decodificada
      : decodificada.convert(numChannels: 3);
  return aplicarMascara(foto, inferir(entradaDelRemovedor(foto)));
}
