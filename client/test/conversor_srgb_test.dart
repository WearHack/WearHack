/// Comprueba el conversor por tabla y la lectura del nombre del perfil.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wearhack/core/color/conversion.dart';
import 'package:wearhack/core/color/perfil_icc.dart';

import 'helpers/icc_sintetico.dart';

void main() {
  group('ConversorASrgb', () {
    for (final (String nombre, Uint8List bytes) in <(String, Uint8List)>[
      ('Display P3', perfilDisplayP3()),
      ('sRGB', perfilSrgb()),
    ]) {
      test('coincide con perfilASrgb8 en un byte como mucho: $nombre', () {
        final PerfilRgb perfil = PerfilRgb.desdeBytes(bytes);
        final List<int> pixeles = <int>[];
        final List<(int, int, int)> colores = <(int, int, int)>[];
        for (int r = 0; r <= 255; r += 17) {
          for (int g = 0; g <= 255; g += 17) {
            for (int b = 0; b <= 255; b += 17) {
              colores.add((r, g, b));
              pixeles.addAll(<int>[r, g, b]);
            }
          }
        }
        final Uint8List buffer = Uint8List.fromList(pixeles);

        ConversorASrgb(perfil).convertirEnSitio(buffer);

        for (int i = 0; i < colores.length; i++) {
          final (int, int, int) c = colores[i];
          final ({int r, int g, int b}) esperado = perfilASrgb8(
            perfil,
            c.$1,
            c.$2,
            c.$3,
          );
          expect(buffer[i * 3], closeTo(esperado.r, 1), reason: '$c');
          expect(buffer[i * 3 + 1], closeTo(esperado.g, 1), reason: '$c');
          expect(buffer[i * 3 + 2], closeTo(esperado.b, 1), reason: '$c');
        }
      });
    }

    test('un buffer que no es RGB empaquetado se rechaza', () {
      final ConversorASrgb conversor = ConversorASrgb(PerfilRgb.srgb);

      expect(
        () => conversor.convertirEnSitio(Uint8List(10)),
        throwsArgumentError,
      );
    });
  });

  group('nombre del perfil', () {
    PerfilRgb leer({Uint8List? descripcion}) =>
        PerfilRgb.desdeBytes(perfilDisplayP3(descripcion: descripcion));

    // El conteo de un `desc` es la longitud + 1. Con "Display P3" (10 letras)
    // vale 11, que es el codigo del tabulador vertical: un desplazamiento
    // equivocado quedaria oculto por el trim. Por eso hay nombres de otras
    // longitudes.
    test('ICC v2 con nombres de varias longitudes', () {
      for (final String nombre in <String>[
        'sRGB',
        'Perfil de prueba',
        'Display P3 con nombre largo del fabricante',
      ]) {
        expect(leer(descripcion: tagDescV2(nombre)).descripcion, nombre);
      }
    });

    test('ICC v4 con nombres de varias longitudes', () {
      for (final String nombre in <String>['sRGB', 'Perfil de prueba']) {
        expect(leer(descripcion: tagMluc(nombre)).descripcion, nombre);
      }
    });

    test('ICC v2 (desc)', () {
      expect(
        leer(descripcion: tagDescV2('Display P3')).descripcion,
        'Display P3',
      );
    });

    test('ICC v4 (mluc, UTF-16)', () {
      expect(
        leer(descripcion: tagMluc('Display P3')).descripcion,
        'Display P3',
      );
    });

    test('sin tag desc, el nombre es null', () {
      expect(leer().descripcion, isNull);
    });

    test('un nombre ilegible no impide leer los colorantes', () {
      final PerfilRgb p = leer(
        descripcion: tagDescV2('Display P3', conteoDeclarado: 99999),
      );

      expect(p.descripcion, isNull);
      expect(p.rojo.$1, greaterThan(0.4));
    });

    test('el sRGB incorporado se llama sRGB', () {
      expect(PerfilRgb.srgb.descripcion, 'sRGB');
    });
  });
}
