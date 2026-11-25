/// La remocion de fondo sin LiteRT (issue #12): entrada, mascara y recorte.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wearhack/core/clasificacion/removedor_fondo.dart';

const int lado = ladoEntradaRemovedor;

/// Una mascara de 320 x 320 con 1 dentro del rectangulo y 0 fuera.
Float32List mascaraRectangulo(int x0, int y0, int x1, int y1) {
  final Float32List m = Float32List(lado * lado);
  for (int y = y0; y < y1; y++) {
    for (int x = x0; x < x1; x++) {
      m[y * lado + x] = 1;
    }
  }
  return m;
}

img.Image fotoRoja(int ancho, int alto) {
  final img.Image foto = img.Image(width: ancho, height: alto);
  img.fill(foto, color: img.ColorRgb8(200, 20, 30));
  return foto;
}

void main() {
  test('la entrada es la foto en 320 x 320, RGB en [0, 255]', () {
    final Float32List entrada = entradaDelRemovedor(fotoRoja(640, 480));

    expect(entrada.length, lado * lado * 3);
    expect(entrada.sublist(0, 3), <double>[200, 20, 30]);
    expect(entrada.sublist(entrada.length - 3), <double>[200, 20, 30]);
  });

  test('la mascara pasa a ser el alfa y la prenda queda recortada', () {
    // Mitad central en cada eje: en una foto de 640 x 480 es 320 x 240.
    final img.Image prenda = aplicarMascara(
      fotoRoja(640, 480),
      mascaraRectangulo(80, 80, 240, 240),
    );

    expect(prenda.numChannels, 4);
    expect(prenda.width, closeTo(320, 4));
    expect(prenda.height, closeTo(240, 4));
    final img.Pixel centro = prenda.getPixel(
      prenda.width ~/ 2,
      prenda.height ~/ 2,
    );
    expect(centro.a, 255);
    expect(<num>[centro.r, centro.g, centro.b], <num>[200, 20, 30]);
  });

  test('la mascara se normaliza con su minimo y su maximo', () {
    // Una mascara tibia (0,2 fuera, 0,6 dentro) tambien recorta la prenda.
    final Float32List m = Float32List(lado * lado)
      ..fillRange(0, lado * lado, 0.2);
    for (int y = 100; y < 220; y++) {
      for (int x = 100; x < 220; x++) {
        m[y * lado + x] = 0.6;
      }
    }

    final img.Image prenda = aplicarMascara(fotoRoja(lado, lado), m);

    expect(prenda.width, closeTo(120, 2));
    expect(prenda.getPixel(prenda.width ~/ 2, prenda.height ~/ 2).a, 255);
  });

  test('sin primer plano devuelve todo transparente', () {
    final img.Image prenda = aplicarMascara(
      fotoRoja(100, 100),
      Float32List(lado * lado),
    );

    expect(prenda.width, 100);
    expect(prenda.getPixel(50, 50).a, 0);
  });

  test('una mascara de otro tamano es un error', () {
    expect(
      () => aplicarMascara(fotoRoja(10, 10), Float32List(10)),
      throwsFormatException,
    );
  });

  test('quitarFondoConMascara decodifica el JPEG y usa la inferencia', () {
    final Uint8List jpeg = img.encodeJpg(fotoRoja(400, 300), quality: 95);
    Float32List? recibida;

    final img.Image prenda = quitarFondoConMascara(jpeg, (Float32List e) {
      recibida = e;
      return mascaraRectangulo(0, 0, lado ~/ 2, lado);
    });

    expect(recibida!.length, lado * lado * 3);
    expect(prenda.width, closeTo(200, 3));
    expect(prenda.height, 300);
  });

  test('un JPEG roto es un error', () {
    expect(
      () => quitarFondoConMascara(
        Uint8List.fromList(<int>[1, 2, 3]),
        (Float32List e) => Float32List(lado * lado),
      ),
      throwsFormatException,
    );
  });
}
