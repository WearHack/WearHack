/// Comprueba que el perfil ICC se extrae del JPEG sin pasar por ninguna
/// libreria de imagen, y que se reconstruye bien cuando viene en varios
/// segmentos.
///
/// El JPEG base lo genera `image` en memoria; el perfil se inserta a mano con
/// la forma exacta que usa una camara (firma, secuencia y conteo).
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wearhack/core/color/jpeg_icc.dart';
import 'package:wearhack/core/color/perfil_icc.dart';

import 'helpers/icc_sintetico.dart';

Uint8List _jpegSinPerfil() {
  final img.Image im = img.Image(width: 64, height: 64);
  for (final img.Pixel p in im) {
    p
      ..r = p.x * 4
      ..g = p.y * 4
      ..b = 90;
  }
  return img.encodeJpg(im, quality: 90);
}

void main() {
  final Uint8List base = _jpegSinPerfil();

  test('un JPEG sin perfil devuelve null', () {
    expect(extraerIccDeJpeg(base), isNull);
  });

  test('un perfil en un solo segmento sale identico, byte a byte', () {
    final Uint8List perfil = perfilDisplayP3();

    final Uint8List? salida = extraerIccDeJpeg(jpegConIcc(base, perfil));

    expect(salida, perfil);
  });

  test('el perfil extraido se puede leer como Display P3', () {
    final Uint8List perfil = perfilDisplayP3();

    final PerfilRgb leido = PerfilRgb.desdeBytes(
      extraerIccDeJpeg(jpegConIcc(base, perfil))!,
    );

    expect(leido.rojo.$1, closeTo(PerfilRgb.desdeBytes(perfil).rojo.$1, 1e-9));
  });

  test('un perfil grande en varios segmentos se ensambla en orden', () {
    final Uint8List perfil = construirPerfil(
      rojo: PerfilRgb.srgb.rojo,
      verde: PerfilRgb.srgb.verde,
      azul: PerfilRgb.srgb.azul,
      curva: curvaSrgbParametrica(),
      relleno: 150000,
    );

    final Uint8List jpeg = jpegConIcc(base, perfil);

    expect(extraerIccDeJpeg(jpeg), perfil);
  });

  test('los segmentos escritos fuera de orden se reordenan por secuencia', () {
    final Uint8List perfil = construirPerfil(
      rojo: PerfilRgb.srgb.rojo,
      verde: PerfilRgb.srgb.verde,
      azul: PerfilRgb.srgb.azul,
      curva: curvaSrgbParametrica(),
      relleno: 150000,
    );

    final Uint8List jpeg = jpegConIcc(
      base,
      perfil,
      ordenDeEscritura: <int>[2, 0, 1],
    );

    expect(extraerIccDeJpeg(jpeg), perfil);
  });

  test(
    'faltan fragmentos: falla en voz alta en vez de devolver un perfil roto',
    () {
      final Uint8List perfil = construirPerfil(
        rojo: PerfilRgb.srgb.rojo,
        verde: PerfilRgb.srgb.verde,
        azul: PerfilRgb.srgb.azul,
        curva: curvaSrgbParametrica(),
        relleno: 150000,
      );

      final Uint8List jpeg = jpegConIcc(
        base,
        perfil,
        ordenDeEscritura: <int>[0, 2],
      );

      expect(() => extraerIccDeJpeg(jpeg), throwsA(isA<FormatException>()));
    },
  );

  test('algo que no es un JPEG falla con FormatException', () {
    expect(
      () => extraerIccDeJpeg(Uint8List.fromList(<int>[1, 2, 3, 4, 5])),
      throwsA(isA<FormatException>()),
    );
  });

  test('un segmento que se sale del archivo falla con FormatException', () {
    final Uint8List roto = Uint8List.fromList(<int>[
      0xFF, 0xD8, 0xFF, 0xE2, 0xFF, 0xF0, 1, 2, 3, //
    ]);

    expect(() => extraerIccDeJpeg(roto), throwsA(isA<FormatException>()));
  });
}
