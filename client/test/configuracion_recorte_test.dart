/// La configuracion del recorte no inventa valores: lo que no se define, falta.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wearhack/core/recorte/configuracion_recorte.dart';

const Map<String, String> _margenes = <String, String>{
  'RECORTE_MARGEN_SUPERIOR': '0.5',
  'RECORTE_MARGEN_INFERIOR': '0.25',
  'RECORTE_MARGEN_LATERAL': '0.5',
};

void main() {
  test('sin ningun valor, avisa de los tres margenes por su nombre', () {
    try {
      ConfiguracionRecorte.desdeTextos(const <String, String>{});
      fail('debio lanzar');
    } on ConfiguracionRecorteInvalida catch (e) {
      expect(e.problemas, hasLength(3));
      expect(e.toString(), contains('RECORTE_MARGEN_SUPERIOR'));
      expect(e.toString(), contains('RECORTE_MARGEN_INFERIOR'));
      expect(e.toString(), contains('RECORTE_MARGEN_LATERAL'));
      expect(e.toString(), contains('--dart-define'));
    }
  });

  test('el entorno de los tests no define nada, asi que falla', () {
    // Es la prueba de que el codigo no trae valores por defecto escondidos.
    expect(
      ConfiguracionRecorte.desdeEntorno,
      throwsA(isA<ConfiguracionRecorteInvalida>()),
    );
  });

  test('con solo los margenes, los umbrales de calidad quedan sin definir', () {
    final ConfiguracionRecorte c = ConfiguracionRecorte.desdeTextos(_margenes);

    expect(c.margenSuperior, 0.5);
    expect(c.margenInferior, 0.25);
    expect(c.margenLateral, 0.5);
    expect(c.anchoMinimoRostroPx, isNull);
    expect(c.maxQuemadosPct, isNull);
    expect(c.maxNegrosPct, isNull);
    expect(c.nitidezMinima, isNull);
  });

  test('los umbrales opcionales se leen cuando estan', () {
    final ConfiguracionRecorte c = ConfiguracionRecorte.desdeTextos(
      <String, String>{
        ..._margenes,
        'RECORTE_ANCHO_MINIMO_ROSTRO_PX': '180',
        'CALIDAD_MAX_QUEMADOS_PCT': '2.5',
        'CALIDAD_MAX_NEGROS_PCT': '1',
        'CALIDAD_NITIDEZ_MINIMA': '40',
      },
    );

    expect(c.anchoMinimoRostroPx, 180);
    expect(c.maxQuemadosPct, 2.5);
    expect(c.maxNegrosPct, 1);
    expect(c.nitidezMinima, 40);
  });

  test('un texto vacio cuenta como ausente', () {
    final ConfiguracionRecorte c = ConfiguracionRecorte.desdeTextos(
      <String, String>{..._margenes, 'CALIDAD_NITIDEZ_MINIMA': '  '},
    );

    expect(c.nitidezMinima, isNull);
  });

  for (final String malo in <String>['abc', '-1', 'NaN', 'Infinity']) {
    test('el margen "$malo" se rechaza por invalido', () {
      expect(
        () => ConfiguracionRecorte.desdeTextos(<String, String>{
          ..._margenes,
          'RECORTE_MARGEN_SUPERIOR': malo,
        }),
        throwsA(isA<ConfiguracionRecorteInvalida>()),
      );
    });
  }

  test('un porcentaje fuera de 0 a 100 se rechaza', () {
    expect(
      () => ConfiguracionRecorte.desdeTextos(<String, String>{
        ..._margenes,
        'CALIDAD_MAX_QUEMADOS_PCT': '150',
      }),
      throwsA(isA<ConfiguracionRecorteInvalida>()),
    );
  });

  test('reporta todos los problemas juntos, no solo el primero', () {
    try {
      ConfiguracionRecorte.desdeTextos(const <String, String>{
        'RECORTE_MARGEN_SUPERIOR': 'x',
        'CALIDAD_MAX_NEGROS_PCT': '-3',
      });
      fail('debio lanzar');
    } on ConfiguracionRecorteInvalida catch (e) {
      // superior invalido, inferior y lateral ausentes, negros invalido
      expect(e.problemas, hasLength(4));
    }
  });
}
