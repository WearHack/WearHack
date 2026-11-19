import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wearhack/core/color/categoria_color.dart';
import 'package:wearhack/core/color/color_base.dart';
import 'package:wearhack/core/color/conversion.dart';
import 'package:wearhack/core/color/perfil_icc.dart';
import 'package:wearhack/core/vocabulario.dart';

const List<int> _rojo = <int>[220, 20, 20, 255];
const List<int> _azul = <int>[0, 0, 255, 255];
const List<int> _transparente = <int>[0, 0, 0, 0];

Uint8List _imagen(List<List<int>> pixeles) =>
    Uint8List.fromList(<int>[for (final List<int> p in pixeles) ...p]);

List<List<int>> _veces(int n, List<int> pixel) =>
    List<List<int>>.generate(n, (_) => pixel);

ColorLab _lab(int r, int g, int b) => perfilALab(PerfilRgb.srgb, r, g, b);

/// Las categorias se prueban en categoria_color_test.dart.
final TablaIsccNbs _tabla = TablaIsccNbs.desdeJson(
  File(assetTablaIsccNbs).readAsStringSync(),
);

ResultadoColorBase? _calcular(
  List<List<int>> pixeles,
  ConfiguracionColorBase config,
) => calcularColorBase(
  rgba: _imagen(pixeles),
  ancho: pixeles.length,
  alto: 1,
  configuracion: config,
);

const ConfiguracionColorBase _kmeans2 = ConfiguracionColorBase(
  metodo: MetodoColorBase.kmeans,
  k: 2,
  sombrasPct: 0,
  brillosPct: 0,
);

const ConfiguracionColorBase _moda = ConfiguracionColorBase(
  metodo: MetodoColorBase.moda,
  sombrasPct: 0,
  brillosPct: 0,
);

void main() {
  group('ConfiguracionColorBase.desdeTextos', () {
    test('sin nada, dice todo lo que falta y no inventa valores', () {
      expect(
        () => ConfiguracionColorBase.desdeTextos(const <String, String>{}),
        throwsA(
          isA<ConfiguracionColorBaseInvalida>().having(
            (ConfiguracionColorBaseInvalida e) => e.problemas,
            'problemas',
            <String>[
              'falta COLOR_METODO (kmeans o moda)',
              'falta COLOR_SOMBRAS_PCT',
              'falta COLOR_BRILLOS_PCT',
            ],
          ),
        ),
      );
    });

    test('k-means exige K; la moda no', () {
      expect(
        () => ConfiguracionColorBase.desdeTextos(const <String, String>{
          'COLOR_METODO': 'kmeans',
          'COLOR_SOMBRAS_PCT': '10',
          'COLOR_BRILLOS_PCT': '5',
        }),
        throwsA(
          isA<ConfiguracionColorBaseInvalida>().having(
            (ConfiguracionColorBaseInvalida e) => e.problemas,
            'problemas',
            <String>['falta COLOR_K'],
          ),
        ),
      );

      final ConfiguracionColorBase moda = ConfiguracionColorBase.desdeTextos(
        const <String, String>{
          'COLOR_METODO': 'moda',
          'COLOR_SOMBRAS_PCT': '10',
          'COLOR_BRILLOS_PCT': '5',
        },
      );
      expect(moda.metodo, MetodoColorBase.moda);
      expect(moda.k, isNull);
    });

    test('lee una configuracion completa', () {
      final ConfiguracionColorBase c = ConfiguracionColorBase.desdeTextos(
        const <String, String>{
          'COLOR_METODO': ' KMeans ',
          'COLOR_K': '3',
          'COLOR_SOMBRAS_PCT': '10',
          'COLOR_BRILLOS_PCT': '2.5',
        },
      );
      expect(c.metodo, MetodoColorBase.kmeans);
      expect(c.k, 3);
      expect(c.sombrasPct, 10);
      expect(c.brillosPct, 2.5);
    });

    test('rechaza metodo desconocido, K malo y porcentajes fuera de rango', () {
      expect(
        () => ConfiguracionColorBase.desdeTextos(const <String, String>{
          'COLOR_METODO': 'media',
          'COLOR_SOMBRAS_PCT': '-1',
          'COLOR_BRILLOS_PCT': 'mucho',
        }),
        throwsA(
          isA<ConfiguracionColorBaseInvalida>().having(
            (ConfiguracionColorBaseInvalida e) => e.problemas.length,
            'cuantos',
            3,
          ),
        ),
      );
      expect(
        () => ConfiguracionColorBase.desdeTextos(const <String, String>{
          'COLOR_METODO': 'kmeans',
          'COLOR_K': '0',
          'COLOR_SOMBRAS_PCT': '1',
          'COLOR_BRILLOS_PCT': '1',
        }),
        throwsA(isA<ConfiguracionColorBaseInvalida>()),
      );
    });

    test('sombras y brillos no pueden sumar 100 o mas', () {
      expect(
        () => ConfiguracionColorBase.desdeTextos(const <String, String>{
          'COLOR_METODO': 'moda',
          'COLOR_SOMBRAS_PCT': '60',
          'COLOR_BRILLOS_PCT': '40',
        }),
        throwsA(isA<ConfiguracionColorBaseInvalida>()),
      );
    });
  });

  group('calcularColorBase', () {
    test('una prenda lisa da su color, con proporcion 1', () {
      for (final ConfiguracionColorBase config in <ConfiguracionColorBase>[
        _kmeans2,
        _moda,
      ]) {
        final ResultadoColorBase r = _calcular(_veces(50, _rojo), config)!;
        expect(distanciaLab(r.color, _lab(220, 20, 20)), lessThan(0.01));
        expect(r.proporcion, 1);
        expect(r.pixelesAnalizados, 50);
      }
    });

    test('sin ningun pixel opaco no hay color', () {
      expect(_calcular(_veces(10, _transparente), _moda), isNull);
    });

    test('el fondo transparente no cuenta', () {
      final List<List<int>> pixeles = <List<int>>[
        ..._veces(90, _transparente),
        ..._veces(10, _azul),
      ];
      final ResultadoColorBase r = _calcular(pixeles, _kmeans2)!;
      expect(r.pixelesOpacos, 10);
      expect(distanciaLab(r.color, _lab(0, 0, 255)), lessThan(0.01));
    });

    test('con dos colores gana el que mas pixeles tiene', () {
      final List<List<int>> pixeles = <List<int>>[
        ..._veces(70, _rojo),
        ..._veces(30, _azul),
      ];
      for (final ConfiguracionColorBase config in <ConfiguracionColorBase>[
        _kmeans2,
        _moda,
      ]) {
        final ResultadoColorBase r = _calcular(pixeles, config)!;
        expect(distanciaLab(r.color, _lab(220, 20, 20)), lessThan(0.01));
        expect(r.proporcion, closeTo(0.7, 1e-9));
      }
    });

    test('descarta sombras y brillos por luminosidad', () {
      final List<List<int>> pixeles = <List<int>>[
        ..._veces(10, <int>[0, 0, 0, 255]),
        ..._veces(80, <int>[128, 128, 128, 255]),
        ..._veces(10, <int>[255, 255, 255, 255]),
      ];
      final ResultadoColorBase r = _calcular(
        pixeles,
        const ConfiguracionColorBase(
          metodo: MetodoColorBase.kmeans,
          k: 1,
          sombrasPct: 10,
          brillosPct: 10,
        ),
      )!;
      expect(r.descartadosSombras, 10);
      expect(r.descartadosBrillos, 10);
      expect(r.pixelesAnalizados, 80);
      expect(distanciaLab(r.color, _lab(128, 128, 128)), lessThan(0.01));
    });

    test('sin descartar nada, una prenda negra sigue siendo negra', () {
      final ResultadoColorBase r = _calcular(
        _veces(40, <int>[0, 0, 0, 255]),
        _moda,
      )!;
      expect(_tabla.categoria(r.color), CategoriaColor.negro);
    });

    test('muestrea las imagenes grandes', () {
      final Uint8List rgba = _imagen(_veces(200 * 200, _rojo));
      final ResultadoColorBase r = calcularColorBase(
        rgba: rgba,
        ancho: 200,
        alto: 200,
        configuracion: const ConfiguracionColorBase(
          metodo: MetodoColorBase.moda,
          sombrasPct: 0,
          brillosPct: 0,
          maxPixeles: 100,
        ),
      )!;
      expect(r.pixelesOpacos, 40000);
      expect(r.pixelesAnalizados, lessThanOrEqualTo(100));
    });

    test('es repetible: el mismo dato da el mismo color', () {
      final List<List<int>> pixeles = <List<int>>[
        for (int i = 0; i < 300; i++)
          <int>[(i * 7) % 256, (i * 13) % 256, i % 256, 255],
      ];
      const ConfiguracionColorBase config = ConfiguracionColorBase(
        metodo: MetodoColorBase.kmeans,
        k: 4,
        sombrasPct: 5,
        brillosPct: 5,
      );
      final ResultadoColorBase a = _calcular(pixeles, config)!;
      final ResultadoColorBase b = _calcular(pixeles, config)!;
      expect(a.color.l, b.color.l);
      expect(a.color.a, b.color.a);
      expect(a.color.b, b.color.b);
    });

    test('k mayor que los pixeles no falla', () {
      final ResultadoColorBase r = _calcular(
        _veces(2, _rojo),
        const ConfiguracionColorBase(
          metodo: MetodoColorBase.kmeans,
          k: 8,
          sombrasPct: 0,
          brillosPct: 0,
        ),
      )!;
      expect(r.pixelesAnalizados, 2);
    });

    test('un buffer del tamano equivocado es un error', () {
      expect(
        () => calcularColorBase(
          rgba: Uint8List(10),
          ancho: 2,
          alto: 2,
          configuracion: _moda,
        ),
        throwsArgumentError,
      );
    });
  });
}
