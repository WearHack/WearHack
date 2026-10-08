/// La guia de distancia: clasificacion, lectura del rango y textos.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wearhack/features/captura_pruebas/modelos.dart';
import 'package:wearhack/features/captura_pruebas/ui/guia_de_distancia.dart';

void main() {
  const RangoDeAncho rango = RangoDeAncho(minimo: 380, maximo: 520);

  group('clasificarDistancia', () {
    test('sin rango no se puede decir nada: sin calibrar', () {
      expect(clasificarDistancia(450, null), EstadoDeDistancia.sinCalibrar);
      expect(clasificarDistancia(null, null), EstadoDeDistancia.sinCalibrar);
    });

    test('con rango y sin rostro', () {
      expect(clasificarDistancia(null, rango), EstadoDeDistancia.sinRostro);
    });

    test('por debajo del minimo esta lejos', () {
      expect(clasificarDistancia(379, rango), EstadoDeDistancia.muyLejos);
      expect(clasificarDistancia(100, rango), EstadoDeDistancia.muyLejos);
    });

    test('por encima del maximo esta cerca', () {
      expect(clasificarDistancia(521, rango), EstadoDeDistancia.muyCerca);
      expect(clasificarDistancia(900, rango), EstadoDeDistancia.muyCerca);
    });

    test('dentro del rango esta bien, y los bordes cuentan como bien', () {
      expect(clasificarDistancia(380, rango), EstadoDeDistancia.bien);
      expect(clasificarDistancia(450, rango), EstadoDeDistancia.bien);
      expect(clasificarDistancia(520, rango), EstadoDeDistancia.bien);
    });
  });

  group('RangoDeAncho.desdeTexto', () {
    test('lee "min-max", con o sin espacios', () {
      final RangoDeAncho? a = RangoDeAncho.desdeTexto('380-520');
      final RangoDeAncho? b = RangoDeAncho.desdeTexto('  380 - 520 ');

      expect((a!.minimo, a.maximo), (380, 520));
      expect((b!.minimo, b.maximo), (380, 520));
    });

    test('un rango de un solo valor es valido', () {
      final RangoDeAncho? r = RangoDeAncho.desdeTexto('400-400');

      expect((r!.minimo, r.maximo), (400, 400));
    });

    for (final String malo in <String>[
      '',
      '   ',
      'abc',
      '380',
      '380-',
      '-520',
      '520-380',
      '0-100',
      '380-520-600',
      '380_520',
      '3.8-5.2',
      '-380-520',
    ]) {
      test('"$malo" no es un rango', () {
        expect(RangoDeAncho.desdeTexto(malo), isNull);
      });
    }
  });

  test('sin --dart-define no hay rango calibrado para ningun celular', () {
    // Es la prueba de que el codigo no trae un rango por defecto escondido.
    for (final CodigoCelular c in CodigoCelular.values) {
      expect(rangoDeDistanciaDelEntorno(c), isNull, reason: c.codigo);
    }
  });

  group('textos', () {
    test(
      'sin calibrar muestra el ancho medido, que es lo que sirve para calibrar',
      () {
        expect(
          textoDeDistancia(EstadoDeDistancia.sinCalibrar, 433),
          contains('433 px'),
        );
        expect(
          textoDeDistancia(EstadoDeDistancia.sinCalibrar, null),
          isNot(contains('px')),
        );
      },
    );

    test('cada estado dice algo distinto y accionable', () {
      final Set<String> textos = <String>{
        for (final EstadoDeDistancia e in EstadoDeDistancia.values)
          textoDeDistancia(e, 450),
      };

      expect(textos, hasLength(EstadoDeDistancia.values.length));
      expect(
        textoDeDistancia(EstadoDeDistancia.muyLejos, null),
        contains('Acercate'),
      );
      expect(
        textoDeDistancia(EstadoDeDistancia.muyCerca, null),
        contains('Alejate'),
      );
    });
  });
}
