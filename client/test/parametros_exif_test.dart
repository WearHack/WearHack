/// Los parametros de camara salen del EXIF de la foto; lo que no venga, es null.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wearhack/features/captura_pruebas/metadatos.dart';
import 'package:wearhack/features/captura_pruebas/parametros_exif.dart';

const int _tagExposureTime = 0x829a;
const int _tagIsoSpeed = 0x8827;
const int _tagWhiteBalance = 0xa403;

Uint8List _jpegConExif({
  img.IfdValue? exposicion,
  img.IfdValue? iso,
  img.IfdValue? balance,
}) {
  final img.Image im = img.Image(width: 32, height: 32);
  for (final img.Pixel p in im) {
    p
      ..r = 120
      ..g = 90
      ..b = 80;
  }
  if (exposicion != null) im.exif.exifIfd[_tagExposureTime] = exposicion;
  if (iso != null) im.exif.exifIfd[_tagIsoSpeed] = iso;
  if (balance != null) im.exif.exifIfd[_tagWhiteBalance] = balance;
  return img.encodeJpg(im, quality: 90);
}

void main() {
  test('lee tiempo de exposicion, ISO y balance de blancos', () {
    final ParametrosDeCamara p = leerParametrosDeCamara(
      _jpegConExif(
        exposicion: img.IfdValueRational(1, 60),
        iso: img.IfdValueLong(400),
        balance: img.IfdValueShort(0),
      ),
    );

    expect(p.exposicion, closeTo(1 / 60, 1e-6));
    expect(p.iso, 400);
    expect(p.balanceBlancos, 'auto');
  });

  test('el balance de blancos manual se llama manual', () {
    final ParametrosDeCamara p = leerParametrosDeCamara(
      _jpegConExif(balance: img.IfdValueShort(1)),
    );

    expect(p.balanceBlancos, 'manual');
  });

  test('un valor de balance que no es 0 ni 1 queda en null', () {
    final ParametrosDeCamara p = leerParametrosDeCamara(
      _jpegConExif(balance: img.IfdValueShort(7)),
    );

    expect(p.balanceBlancos, isNull);
  });

  test('lo que el EXIF no trae queda en null, no inventado', () {
    final ParametrosDeCamara p = leerParametrosDeCamara(
      _jpegConExif(iso: img.IfdValueLong(100)),
    );

    expect(p.iso, 100);
    expect(p.exposicion, isNull);
    expect(p.balanceBlancos, isNull);
  });

  test('un JPEG sin EXIF da parametros vacios', () {
    final ParametrosDeCamara p = leerParametrosDeCamara(_jpegConExif());

    expect(p.exposicion, isNull);
    expect(p.iso, isNull);
    expect(p.balanceBlancos, isNull);
  });

  test('valores imposibles (exposicion cero, ISO cero) quedan en null', () {
    final ParametrosDeCamara p = leerParametrosDeCamara(
      _jpegConExif(
        exposicion: img.IfdValueRational(0, 1),
        iso: img.IfdValueLong(0),
      ),
    );

    expect(p.exposicion, isNull);
    expect(p.iso, isNull);
  });

  test('bytes que no son un JPEG no lanzan: dan parametros vacios', () {
    for (final Uint8List malo in <Uint8List>[
      Uint8List(0),
      Uint8List.fromList(<int>[1, 2, 3, 4, 5]),
      Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE1, 0xFF, 0xFF, 0x00]),
    ]) {
      final ParametrosDeCamara p = leerParametrosDeCamara(malo);

      expect(p.iso, isNull);
      expect(p.exposicion, isNull);
      expect(p.balanceBlancos, isNull);
    }
  });
}
