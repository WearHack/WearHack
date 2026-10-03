/// Guarda reglas de `docs/spec-modo-captura-pruebas.md` que no se pueden probar
/// de otra forma sin un telefono: **solo builds internas**, **sin red** y **fuera
/// de la galeria**.
///
/// Es una prueba estatica sobre el codigo. Usa listas blancas de imports por
/// zona: si alguien necesita un import nuevo, este test falla y obliga a
/// decidirlo a proposito, en lugar de colarse en un commit.
///
/// Las zonas son tres:
///
/// - la **logica** (`lib/features/captura_pruebas/*.dart`): sin plugins ni Flutter
/// - las **pantallas** (`lib/features/captura_pruebas/ui/`): Flutter, pero ningun
///   plugin de plataforma; reciben todo por `DependenciasCaptura`
/// - la **plataforma** (`lib/platform/captura_pruebas/`): los plugins de camara,
///   dispositivo y compartir, y nada de red
///
/// No sustituye la comprobacion con un proxy o el inspector de red en el celular
/// (criterio de aceptacion de la spec): la complementa.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const List<String> _importsDeLaLogica = <String>[
  'dart:convert',
  'dart:io',
  'dart:typed_data',
  'package:archive/archive_io.dart',
  'package:crypto/crypto.dart',
  // Solo para leer el EXIF de la foto, sin decodificar los pixeles.
  'package:image/image.dart',
  'package:path/path.dart',
  'package:wearhack/core/recorte/controles_calidad.dart',
  'package:wearhack/core/recorte/recortador_facial.dart',
  'package:wearhack/features/captura_pruebas/',
  'package:wearhack/platform/captura/contratos.dart',
];

const List<String> _importsDeLasPantallas = <String>[
  'dart:async',
  'dart:io',
  'dart:typed_data',
  'package:flutter/',
  'package:path/path.dart',
  'package:wearhack/core/',
  'package:wearhack/features/captura_pruebas/',
];

const List<String> _importsDeLaPlataforma = <String>[
  'dart:async',
  'dart:io',
  'dart:math',
  'package:camera/camera.dart',
  'package:device_info_plus/device_info_plus.dart',
  'package:flutter/',
  'package:google_mlkit_face_detection/google_mlkit_face_detection.dart',
  'package:package_info_plus/package_info_plus.dart',
  'package:path/path.dart',
  'package:path_provider/path_provider.dart',
  'package:share_plus/share_plus.dart',
  'package:wearhack/core/configuracion.dart',
  'package:wearhack/features/captura_pruebas/',
  'package:wearhack/platform/captura.dart',
  'package:wearhack/platform/captura/contratos.dart',
];

/// Cosas que significarian red o galeria si aparecieran en el codigo.
const List<String> _prohibidos = <String>[
  'HttpClient',
  'HttpServer',
  'WebSocket',
  'Socket.connect',
  'RawSocket',
  'Uri.http',
  'Uri.https',
  'http.get',
  'http.post',
  'package:http',
  'package:dio',
  'package:firebase',
  'gallery',
  'galeria',
  'MediaStore',
  'PHPhotoLibrary',
  'saveImage',
];

List<File> _dartEn(String carpeta) => <File>[
  for (final FileSystemEntity e in Directory(carpeta).listSync(recursive: true))
    if (e is File && e.path.endsWith('.dart')) e,
];

String _normal(String ruta) => ruta.replaceAll('\\', '/');

final String _carpetaDelModo = p.join('lib', 'features', 'captura_pruebas');
final String _carpetaDePantallas = p.join(_carpetaDelModo, 'ui');
final String _carpetaDePlataforma = p.join(
  'lib',
  'platform',
  'captura_pruebas',
);

/// El codigo sin comentarios, para no marcar una palabra que solo se explica.
String _sinComentarios(String fuente) => fuente
    .split('\n')
    .where((String l) => !l.trimLeft().startsWith('//'))
    .join('\n');

final RegExp _importacion = RegExp(
  r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

List<String> _importsFueraDeLista(List<File> fuentes, List<String> permitidos) {
  final List<String> intrusos = <String>[];
  for (final File f in fuentes) {
    for (final RegExpMatch m in _importacion.allMatches(
      _sinComentarios(f.readAsStringSync()),
    )) {
      final String destino = m.group(1)!;
      if (!permitidos.any(destino.startsWith)) {
        intrusos.add('${_normal(f.path)}: $destino');
      }
    }
  }
  return intrusos;
}

List<String> _prohibidosEn(List<File> fuentes) {
  final List<String> hallazgos = <String>[];
  for (final File f in fuentes) {
    final String codigo = _sinComentarios(f.readAsStringSync());
    for (final String palabra in _prohibidos) {
      if (codigo.contains(palabra)) {
        hallazgos.add('${_normal(f.path)} contiene "$palabra"');
      }
    }
  }
  return hallazgos;
}

void main() {
  final List<File> todas = _dartEn(_carpetaDelModo);
  final List<File> pantallas = _dartEn(_carpetaDePantallas);
  final List<File> logica = <File>[
    for (final File f in todas)
      if (!_normal(f.path).contains('/ui/')) f,
  ];
  final List<File> plataforma = _dartEn(_carpetaDePlataforma);

  group('no son pruebas vacias', () {
    test('encuentra el codigo de cada zona', () {
      expect(logica.length, greaterThanOrEqualTo(6));
      expect(pantallas.length, greaterThanOrEqualTo(6));
      expect(plataforma.length, greaterThanOrEqualTo(2));
    });
  });

  group('imports permitidos', () {
    const String razon =
        'Un import nuevo se decide a proposito: agregalo a la lista blanca de '
        'este test, con su razon.';

    test('la logica no importa plugins ni Flutter', () {
      expect(
        _importsFueraDeLista(logica, _importsDeLaLogica),
        isEmpty,
        reason: razon,
      );
    });

    test('las pantallas importan Flutter pero ningun plugin de plataforma', () {
      expect(
        _importsFueraDeLista(pantallas, _importsDeLasPantallas),
        isEmpty,
        reason: razon,
      );
    });

    test('la plataforma importa solo los plugins previstos', () {
      expect(
        _importsFueraDeLista(plataforma, _importsDeLaPlataforma),
        isEmpty,
        reason: razon,
      );
    });
  });

  group('sin red ni galeria', () {
    test('la logica y las pantallas no usan nada de red ni de galeria', () {
      expect(_prohibidosEn(todas), isEmpty);
    });

    test('la plataforma tampoco', () {
      expect(_prohibidosEn(plataforma), isEmpty);
    });
  });

  group('solo en builds internas', () {
    /// Archivos fuera de [carpeta] cuyo codigo (sin comentarios) contiene [texto].
    List<String> importadores(String texto, {required List<String> excluir}) =>
        <String>[
          for (final File f in _dartEn('lib'))
            if (!excluir.any((String x) => _normal(f.path).startsWith(x)) &&
                _sinComentarios(f.readAsStringSync()).contains(texto))
              _normal(f.path),
        ];

    test('solo la plataforma de movil importa el codigo del modo', () {
      expect(
        importadores(
          'features/captura_pruebas/',
          excluir: <String>['lib/features/captura_pruebas/'],
        ),
        <String>['lib/platform/captura_pruebas/captura_pruebas_movil.dart'],
      );
    });

    test('solo main.dart importa el punto de entrada de la plataforma', () {
      expect(
        importadores(
          'platform/captura_pruebas.dart',
          excluir: <String>['lib/platform/captura_pruebas.dart'],
        ),
        <String>['lib/main.dart'],
      );
    });

    test(
      'main.dart solo llama al modo detras de Configuracion.capturaPruebas',
      () {
        final List<String> lineas = File(p.join('lib', 'main.dart'))
            .readAsStringSync()
            .split('\n');
        final List<int> llamadas = <int>[
          for (int i = 0; i < lineas.length; i++)
            if (lineas[i].contains('abrirCapturaPruebas(')) i,
        ];

        expect(
          llamadas,
          isNotEmpty,
          reason: 'si ya no hay llamada, este test sobra',
        );
        for (final int i in llamadas) {
          final String antes = lineas
              .sublist(i > 8 ? i - 8 : 0, i + 1)
              .join('\n');
          expect(
            antes,
            contains('if (Configuracion.capturaPruebas)'),
            reason: 'la llamada de la linea ${i + 1} no esta detras del flag',
          );
        }
      },
    );

    test('el flag vale falso por defecto', () {
      final String fuente = File(p.join('lib', 'core', 'configuracion.dart'))
          .readAsStringSync();

      expect(fuente, contains("bool.fromEnvironment('CAPTURA_PRUEBAS')"));
      expect(
        fuente.contains(
          "bool.fromEnvironment('CAPTURA_PRUEBAS', defaultValue: true)",
        ),
        isFalse,
      );
    });

    test('la guia de distancia en vivo tambien esta apagada por defecto', () {
      final String fuente = File(p.join('lib', 'core', 'configuracion.dart'))
          .readAsStringSync();

      expect(fuente, contains("'CAPTURA_GUIA_EN_VIVO'"));
      expect(fuente.contains('defaultValue: true'), isFalse);
    });
  });
}
