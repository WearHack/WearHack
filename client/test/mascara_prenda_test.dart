import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wearhack/core/clasificacion/removedor_fondo.dart';

void main() {
  const int lado = 320;
  final img.Image imagen = img.Image(width: lado, height: lado);
  img.fill(imagen, color: img.ColorRgb8(133, 42, 61));

  test('rechaza una máscara que conserva solo un fragmento del borde', () {
    final Float32List mascara = Float32List(lado * lado);
    mascara.fillRange(lado * 312, mascara.length, 1);

    expect(
      () => aplicarMascara(imagen, mascara),
      throwsA(isA<EncuadrePrendaInsuficiente>()),
    );
  });

  test('recorta el margen y conserva el color del contenido de la máscara', () {
    final Float32List mascara = Float32List(lado * lado);
    for (int y = 64; y < 256; y++) {
      mascara.fillRange(y * lado + 96, y * lado + 224, 1);
    }
    mascara[70 * lado + 105] = 0;

    final img.Image prenda = aplicarMascara(imagen, mascara);
    expect((prenda.width, prenda.height), (128, 192));
    final img.Pixel opaco = prenda.getPixel(0, 0);
    expect((opaco.r, opaco.g, opaco.b, opaco.a), (133, 42, 61, 255));
    final img.Pixel transparente = prenda.getPixel(9, 6);
    expect(
      (transparente.r, transparente.g, transparente.b, transparente.a),
      (0, 0, 0, 0),
    );
  });
}
