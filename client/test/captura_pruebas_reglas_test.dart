/// Guarda dos reglas de `docs/spec-modo-captura-pruebas.md` que no se pueden
/// probar de otra forma sin un telefono: **sin red** y **fuera de la galeria**.
///
/// Es una prueba estatica sobre el codigo de `lib/features/captura_pruebas/`.
/// Usa una lista blanca de imports: si alguien necesita uno nuevo, este test
/// falla y obliga a decidirlo a proposito, en lugar de colarse en un commit.
///
/// No sustituye la comprobacion con un proxy o el inspector de red en el
/// celular (criterio de aceptacion de la spec): la complementa.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const List<String> _importsPermitidos = <String>[
  'dart:convert',
  'dart:io',
  'dart:typed_data',
  'package:archive/archive_io.dart',
  'package:crypto/crypto.dart',
  'package:path/path.dart',
  // El propio proyecto: solo lo necesario, sin plugins de plataforma.
  'package:wearhack/core/recorte/recortador_facial.dart',
  'package:wearhack/features/captura_pruebas/',
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

List<File> _fuentes() {
  final Directory dir = Directory(p.join('lib', 'features', 'captura_pruebas'));
  return <File>[
    for (final FileSystemEntity e in dir.listSync(recursive: true))
      if (e is File && e.path.endsWith('.dart')) e,
  ];
}

/// El codigo sin comentarios, para no marcar una palabra que solo se explica.
String _sinComentarios(String fuente) => fuente
    .split('\n')
    .where((String l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  final List<File> fuentes = _fuentes();

  test(
    'encuentra el codigo de la captura de pruebas (la prueba no es vacia)',
    () {
      expect(fuentes.length, greaterThanOrEqualTo(5));
    },
  );

  test('solo importa lo permitido', () {
    final RegExp importacion = RegExp(
      r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
      multiLine: true,
    );
    final List<String> intrusos = <String>[];
    for (final File f in fuentes) {
      for (final RegExpMatch m in importacion.allMatches(
        _sinComentarios(f.readAsStringSync()),
      )) {
        final String destino = m.group(1)!;
        if (!_importsPermitidos.any(destino.startsWith)) {
          intrusos.add('${p.basename(f.path)}: $destino');
        }
      }
    }

    expect(
      intrusos,
      isEmpty,
      reason: 'Un import nuevo se decide a proposito: agregalo a la lista blanca de este test, con su razon.',
    );
  });

  test('no usa nada de red ni de galeria', () {
    final List<String> hallazgos = <String>[];
    for (final File f in fuentes) {
      final String codigo = _sinComentarios(f.readAsStringSync());
      for (final String palabra in _prohibidos) {
        if (codigo.contains(palabra)) {
          hallazgos.add('${p.basename(f.path)} contiene "$palabra"');
        }
      }
    }

    expect(hallazgos, isEmpty);
  });

  test('el modo no se alcanza sin el flag: nada de la app lo importa todavia', () {
    // Mientras no exista la pantalla, ningun archivo fuera de la propia carpeta
    // debe importar la captura de pruebas. Cuando se anada la pantalla, este
    // test se reemplaza por uno que exija que el unico import este detras de
    // `Configuracion.capturaPruebas`.
    final List<String> importadores = <String>[
      for (final FileSystemEntity e in Directory(
        'lib',
      ).listSync(recursive: true))
        if (e is File &&
            e.path.endsWith('.dart') &&
            !e.path.contains(p.join('features', 'captura_pruebas')) &&
            e.readAsStringSync().contains('features/captura_pruebas/'))
          e.path,
    ];

    expect(importadores, isEmpty);
  });
}
