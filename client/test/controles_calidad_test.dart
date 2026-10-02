/// Los controles de calidad siempre se miden; solo fallan si hay umbral.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wearhack/core/recorte/configuracion_recorte.dart';
import 'package:wearhack/core/recorte/controles_calidad.dart';

const int _lado = 64;

Uint8List _solido(int r, int g, int b) {
  final Uint8List px = Uint8List(_lado * _lado * 3);
  for (int i = 0; i < px.length; i += 3) {
    px[i] = r;
    px[i + 1] = g;
    px[i + 2] = b;
  }
  return px;
}

/// Tablero de ajedrez de casillas de 1 pixel: el maximo de detalle.
Uint8List _tablero() {
  final Uint8List px = Uint8List(_lado * _lado * 3);
  for (int y = 0; y < _lado; y++) {
    for (int x = 0; x < _lado; x++) {
      final int v = (x + y).isEven ? 40 : 200;
      final int i = (y * _lado + x) * 3;
      px[i] = v;
      px[i + 1] = v;
      px[i + 2] = v;
    }
  }
  return px;
}

/// Lo mismo, pero con cada pixel promediado con sus vecinos: desenfocado.
Uint8List _tableroBorroso() {
  final Uint8List nitido = _tablero();
  final Uint8List px = Uint8List(nitido.length);
  for (int y = 0; y < _lado; y++) {
    for (int x = 0; x < _lado; x++) {
      int suma = 0;
      int n = 0;
      for (int dy = -2; dy <= 2; dy++) {
        for (int dx = -2; dx <= 2; dx++) {
          final int xx = (x + dx).clamp(0, _lado - 1);
          final int yy = (y + dy).clamp(0, _lado - 1);
          suma += nitido[(yy * _lado + xx) * 3];
          n++;
        }
      }
      final int i = (y * _lado + x) * 3;
      px[i] = px[i + 1] = px[i + 2] = suma ~/ n;
    }
  }
  return px;
}

ConfiguracionRecorte _config({
  int? ancho,
  double? quemados,
  double? negros,
  double? nitidez,
}) => ConfiguracionRecorte(
  margenSuperior: 0,
  margenInferior: 0,
  margenLateral: 0,
  anchoMinimoRostroPx: ancho,
  maxQuemadosPct: quemados,
  maxNegrosPct: negros,
  nitidezMinima: nitidez,
);

ControlesCalidad _medir(
  Uint8List px,
  ConfiguracionRecorte c, {
  int rostro = 200,
}) => medirCalidad(
  px,
  ancho: _lado,
  alto: _lado,
  anchoRostroPx: rostro,
  configuracion: c,
);

void main() {
  group('medicion', () {
    test('todo blanco: 100 % quemado, 0 % negro', () {
      final ControlesCalidad m = _medir(_solido(255, 255, 255), _config());

      expect(m.porcentajeQuemados, 100);
      expect(m.porcentajeNegros, 0);
    });

    test('todo negro: 100 % negro, 0 % quemado', () {
      final ControlesCalidad m = _medir(_solido(0, 0, 0), _config());

      expect(m.porcentajeNegros, 100);
      expect(m.porcentajeQuemados, 0);
    });

    test('un solo canal saturado ya cuenta como quemado', () {
      final ControlesCalidad m = _medir(_solido(255, 120, 90), _config());

      expect(m.porcentajeQuemados, 100);
    });

    test('un negro casi negro no cuenta: la definicion es estricta', () {
      final ControlesCalidad m = _medir(_solido(1, 0, 0), _config());

      expect(m.porcentajeNegros, 0);
    });

    test('un color liso tiene nitidez cero', () {
      expect(_medir(_solido(120, 90, 80), _config()).nitidez, 0);
    });

    test('un tablero nitido es mas nitido que el mismo desenfocado', () {
      final double nitido = _medir(_tablero(), _config()).nitidez;
      final double borroso = _medir(_tableroBorroso(), _config()).nitidez;

      expect(nitido, greaterThan(borroso * 10));
    });

    test(
      'un pixel brillante en un campo negro da la nitidez calculada a mano',
      () {
        // Laplaciano de un pixel aislado de luminancia 255: 4*255 = 1020 en el
        // centro y -255 en cada uno de sus 4 vecinos; el resto es 0.
        // Interior de 62x62 = 3844 pixeles. Media = 0, asi que la varianza es
        // (1020^2 + 4 * 255^2) / 3844.
        final Uint8List px = _solido(0, 0, 0);
        final int centro = (32 * _lado + 32) * 3;
        px[centro] = px[centro + 1] = px[centro + 2] = 255;

        final double esperado = (1020 * 1020 + 4 * 255 * 255) / 3844;

        expect(_medir(px, _config()).nitidez, closeTo(esperado, 1e-6));
      },
    );

    test('la mitad de los pixeles quemados da 50 %', () {
      final Uint8List px = _solido(100, 100, 100);
      for (int i = 0; i < px.length ~/ 2; i += 3) {
        px[i] = 255;
      }

      expect(_medir(px, _config()).porcentajeQuemados, closeTo(50, 0.1));
    });
  });

  group('umbrales', () {
    test('sin umbrales nada falla, aunque todo este en el extremo', () {
      final ControlesCalidad m = _medir(
        _solido(255, 255, 255),
        _config(),
        rostro: 1,
      );

      expect(m.fallidos, isEmpty);
      expect(m.pasa, isTrue);
      expect(m.recomendaciones, isEmpty);
    });

    test('rostro mas chico que el minimo falla', () {
      final ControlesCalidad m = _medir(
        _solido(120, 90, 80),
        _config(ancho: 300),
        rostro: 200,
      );

      expect(m.fallidos, <ControlCalidad>[ControlCalidad.rostroPequeno]);
    });

    test('rostro igual al minimo pasa', () {
      expect(_medir(_solido(120, 90, 80), _config(ancho: 200)).pasa, isTrue);
    });

    test('demasiados quemados falla', () {
      final ControlesCalidad m = _medir(
        _solido(255, 255, 255),
        _config(quemados: 5),
      );

      expect(m.fallidos, <ControlCalidad>[ControlCalidad.demasiadosQuemados]);
    });

    test('demasiados negros falla', () {
      final ControlesCalidad m = _medir(_solido(0, 0, 0), _config(negros: 5));

      expect(m.fallidos, <ControlCalidad>[ControlCalidad.demasiadosNegros]);
    });

    test('poca nitidez falla', () {
      final ControlesCalidad m = _medir(
        _tableroBorroso(),
        _config(nitidez: 5000),
      );

      expect(m.fallidos, <ControlCalidad>[ControlCalidad.desenfocado]);
    });

    test('cada control fallido trae su recomendacion concreta', () {
      final ControlesCalidad m = _medir(
        _solido(255, 255, 255),
        _config(ancho: 300, quemados: 5, nitidez: 1),
        rostro: 100,
      );

      expect(m.fallidos, hasLength(3));
      expect(m.recomendaciones, hasLength(3));
      expect(
        m.recomendaciones.toSet(),
        hasLength(3),
        reason: 'distintas entre si',
      );
    });
  });

  test('una imagen minuscula no rompe la medicion', () {
    final ControlesCalidad m = medirCalidad(
      Uint8List(3 * 2 * 2),
      ancho: 2,
      alto: 2,
      anchoRostroPx: 10,
      configuracion: _config(),
    );

    expect(m.nitidez, 0);
  });
}
