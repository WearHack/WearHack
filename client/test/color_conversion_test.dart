/// Comprueba la gestion de color del nivel 0: leer un perfil, y pasar de ese
/// espacio a sRGB y a Lab con blanco D65.
///
/// Los perfiles se fabrican en memoria (ver `helpers/icc_sintetico.dart`), asi
/// que ningun test depende de un archivo de perfil.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wearhack/core/color/conversion.dart';
import 'package:wearhack/core/color/perfil_icc.dart';
import 'package:wearhack/core/vocabulario.dart';

import 'helpers/icc_sintetico.dart';

double _deltaE76(ColorLab x, ColorLab y) {
  final double dl = x.l - y.l, da = x.a - y.a, db = x.b - y.b;
  return math.sqrt(dl * dl + da * da + db * db);
}

void main() {
  final PerfilRgb p3 = PerfilRgb.desdeBytes(perfilDisplayP3());
  final PerfilRgb srgb = PerfilRgb.desdeBytes(perfilSrgb());

  group('Lab con blanco D65', () {
    test('el blanco de sRGB da L=100 y a, b en cero', () {
      final ColorLab lab = perfilALab(PerfilRgb.srgb, 255, 255, 255);

      expect(lab.l, closeTo(100, 0.01));
      expect(lab.a, closeTo(0, 0.01));
      expect(lab.b, closeTo(0, 0.01));
    });

    test('el negro da L=0', () {
      expect(perfilALab(PerfilRgb.srgb, 0, 0, 0).l, closeTo(0, 0.01));
    });

    test('el rojo de sRGB coincide con el valor de referencia publicado', () {
      // Referencia: sRGB (255, 0, 0) es Lab (53.24, 80.09, 67.20) con D65.
      final ColorLab lab = perfilALab(PerfilRgb.srgb, 255, 0, 0);

      expect(lab.l, closeTo(53.24, 0.05));
      expect(lab.a, closeTo(80.09, 0.1));
      expect(lab.b, closeTo(67.20, 0.1));
    });

    test('un perfil leido de bytes coincide con el sRGB incorporado', () {
      for (final (int, int, int) c in <(int, int, int)>[
        (200, 150, 120),
        (30, 90, 200),
        (255, 255, 255),
      ]) {
        final ColorLab a = perfilALab(srgb, c.$1, c.$2, c.$3);
        final ColorLab b = perfilALab(PerfilRgb.srgb, c.$1, c.$2, c.$3);
        expect(_deltaE76(a, b), lessThan(0.05), reason: '$c');
      }
    });
  });

  group('Display P3', () {
    test('su blanco es el blanco de sRGB: no se desplaza el neutro', () {
      final ({int r, int g, int b}) c = perfilASrgb8(p3, 255, 255, 255);

      expect((c.r, c.g, c.b), (255, 255, 255));
      final ColorLab lab = perfilALab(p3, 255, 255, 255);
      expect(lab.a.abs(), lessThan(0.05));
      expect(lab.b.abs(), lessThan(0.05));
    });

    test('el rojo de P3 cae fuera de sRGB, con el valor de referencia', () {
      // Referencia publicada: P3 (1, 0, 0) en sRGB lineal es (1.2249, -0.0421, -0.0197).
      final Xyz lineal = perfilASrgbLineal(p3, 255, 0, 0);

      expect(lineal.$1, closeTo(1.2249, 0.002));
      expect(lineal.$2, closeTo(-0.0421, 0.002));
      expect(lineal.$3, closeTo(-0.0197, 0.002));
    });

    test('perfilASrgb8 recorta lo que sRGB no puede mostrar', () {
      final ({int r, int g, int b}) c = perfilASrgb8(p3, 255, 0, 0);

      expect((c.r, c.g, c.b), (255, 0, 0));
    });

    test('los grises se conservan', () {
      final ({int r, int g, int b}) c = perfilASrgb8(p3, 128, 128, 128);

      expect(c.r, closeTo(128, 1));
      expect(c.g, closeTo(128, 1));
      expect(c.b, closeTo(128, 1));
    });

    test('asumir sRGB cuando la foto era P3 desplaza el color medido', () {
      // Un tono de piel. El mismo byte da un Lab distinto segun el perfil.
      final ColorLab comoP3 = perfilALab(p3, 200, 150, 120);
      final ColorLab comoSrgb = perfilALab(srgb, 200, 150, 120);

      expect(_deltaE76(comoP3, comoSrgb), greaterThan(1.0));
      // Y el desplazamiento esta en el croma, que es lo que mueve el subtono.
      expect(
        (comoP3.a - comoSrgb.a).abs() + (comoP3.b - comoSrgb.b).abs(),
        greaterThan(1.0),
      );
    });
  });

  group('sRGB a sRGB', () {
    test('es la identidad, con un byte de margen por el redondeo', () {
      for (int r = 0; r <= 255; r += 51) {
        for (int g = 0; g <= 255; g += 51) {
          for (int b = 0; b <= 255; b += 51) {
            final ({int r, int g, int b}) c = perfilASrgb8(srgb, r, g, b);
            expect(c.r, closeTo(r, 1), reason: '($r, $g, $b)');
            expect(c.g, closeTo(g, 1), reason: '($r, $g, $b)');
            expect(c.b, closeTo(b, 1), reason: '($r, $g, $b)');
          }
        }
      }
    });
  });

  group('curvas', () {
    PerfilRgb conCurva(Uint8List curva) => PerfilRgb.desdeBytes(
      construirPerfil(
        rojo: PerfilRgb.srgb.rojo,
        verde: PerfilRgb.srgb.verde,
        azul: PerfilRgb.srgb.azul,
        curva: curva,
      ),
    );

    test('curv con gamma 2.2 sigue x^2.2', () {
      final PerfilRgb p = conCurva(curvaGamma(2.2));

      // El exponente se guarda en u8Fixed8: 2.2 se redondea a 2.1992, y
      // 0.5^2.1992 = 0.2177.
      expect(p.curvaRojo.aLineal(0.5), closeTo(0.2177, 0.002));
      expect(p.curvaRojo.aLineal(0), 0);
      expect(p.curvaRojo.aLineal(1), closeTo(1, 1e-9));
    });

    test('curv con tabla interpola de forma lineal', () {
      final PerfilRgb p = conCurva(curvaTabla(<int>[0, 32768, 65535]));

      expect(p.curvaRojo.aLineal(0.25), closeTo(0.25, 0.001));
      expect(p.curvaRojo.aLineal(0.75), closeTo(0.75, 0.001));
    });

    test('curv vacia es la identidad', () {
      final PerfilRgb p = conCurva(curvaTabla(<int>[]));

      expect(p.curvaRojo.aLineal(0.37), closeTo(0.37, 1e-9));
    });

    test(
      'para de tipo 3 con los parametros de sRGB iguala a la curva sRGB',
      () {
        final PerfilRgb p = conCurva(curvaSrgbParametrica());

        for (final double v in <double>[0.0, 0.02, 0.04, 0.2, 0.5, 0.9, 1.0]) {
          expect(
            p.curvaRojo.aLineal(v),
            closeTo(CurvaTonal.srgb.aLineal(v), 1e-4),
            reason: 'v=$v',
          );
        }
      },
    );

    test('para de tipo 0 es una potencia', () {
      final PerfilRgb p = conCurva(curvaParametrica(0, <double>[2.0]));

      expect(p.curvaRojo.aLineal(0.5), closeTo(0.25, 1e-4));
    });
  });

  group('perfiles que no se pueden leer', () {
    test('bytes que no son un perfil fallan con FormatException', () {
      expect(
        () => PerfilRgb.desdeBytes(Uint8List(200)),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => PerfilRgb.desdeBytes(Uint8List(10)),
        throwsA(isA<FormatException>()),
      );
    });

    test('un perfil en escala de grises no esta soportado', () {
      final Uint8List gris = construirPerfil(
        rojo: PerfilRgb.srgb.rojo,
        verde: PerfilRgb.srgb.verde,
        azul: PerfilRgb.srgb.azul,
        curva: curvaSrgbParametrica(),
        espacio: 'GRAY',
      );

      expect(
        () => PerfilRgb.desdeBytes(gris),
        throwsA(isA<PerfilIccNoSoportado>()),
      );
    });

    test('un perfil sin colorantes (de LUT) no esta soportado', () {
      final Uint8List lut = construirPerfil(
        rojo: PerfilRgb.srgb.rojo,
        verde: PerfilRgb.srgb.verde,
        azul: PerfilRgb.srgb.azul,
        curva: curvaSrgbParametrica(),
        incluirMatriz: false,
      );

      expect(
        () => PerfilRgb.desdeBytes(lut),
        throwsA(isA<PerfilIccNoSoportado>()),
      );
    });

    test(
      'un perfil truncado falla con FormatException, no con un RangeError',
      () {
        final Uint8List completo = perfilDisplayP3();
        final Uint8List cortado = completo.sublist(0, completo.length - 40);

        expect(
          () => PerfilRgb.desdeBytes(cortado),
          throwsA(isA<FormatException>()),
        );
      },
    );
  });
}
