/// Manifiesto, exportacion a zip y borrado con confirmacion.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wearhack/features/captura_pruebas/almacen_capturas.dart';
import 'package:wearhack/features/captura_pruebas/lote.dart';
import 'package:wearhack/features/captura_pruebas/metadatos.dart';
import 'package:wearhack/features/captura_pruebas/servicio_captura.dart';

import 'helpers/captura_helpers.dart';

EntradaManifiesto _e(String ruta, String sha) =>
    EntradaManifiesto(ruta: ruta, sha256: sha, bytes: 1);

void main() {
  late Directory raiz;

  setUp(() async => raiz = await carpetaTemporal());
  tearDown(() async {
    if (await raiz.exists()) await raiz.delete(recursive: true);
  });

  group('hash global', () {
    test('es el SHA-256 de las lineas "sha  ruta" ordenadas por ruta', () {
      final List<EntradaManifiesto> entradas = <EntradaManifiesto>[
        _e('b.json', 'b' * 64),
        _e('a.jpg', 'a' * 64),
      ];

      final String esperado = sha256
          .convert(utf8.encode('${'a' * 64}  a.jpg\n${'b' * 64}  b.json\n'))
          .toString();

      expect(calcularHashGlobal(entradas), esperado);
    });

    test('no depende del orden en que lleguen las entradas', () {
      final List<EntradaManifiesto> a = <EntradaManifiesto>[
        _e('x.jpg', '1' * 64),
        _e('y.png', '2' * 64),
        _e('z.json', '3' * 64),
      ];

      expect(calcularHashGlobal(a), calcularHashGlobal(a.reversed.toList()));
    });

    test('cambia si cambia un hash o un nombre', () {
      final String base = calcularHashGlobal(<EntradaManifiesto>[
        _e('x.jpg', '1' * 64),
      ]);

      expect(
        calcularHashGlobal(<EntradaManifiesto>[_e('x.jpg', '2' * 64)]),
        isNot(base),
      );
      expect(
        calcularHashGlobal(<EntradaManifiesto>[_e('y.jpg', '1' * 64)]),
        isNot(base),
      );
    });

    test('el orden es el ordinal de los nombres, no el del idioma', () {
      // "B" (66) va antes que "a" (97) en orden ordinal.
      final String ordinal = sha256
          .convert(utf8.encode('${'1' * 64}  B.jpg\n${'2' * 64}  a.jpg\n'))
          .toString();

      expect(
        calcularHashGlobal(<EntradaManifiesto>[
          _e('a.jpg', '2' * 64),
          _e('B.jpg', '1' * 64),
        ]),
        ordinal,
      );
    });
  });

  group('manifiesto del almacen', () {
    test('lista los archivos con su SHA-256 y su tamano', () async {
      final AlmacenCapturas almacen = await almacenConTomas(raiz, 2);

      final Manifiesto m = await calcularManifiesto(almacen);

      expect(m.entradas, hasLength(6));
      for (final EntradaManifiesto e in m.entradas) {
        final File f = File(p.join(almacen.dirTomas.path, e.ruta));
        expect(e.sha256, sha256.convert(f.readAsBytesSync()).toString());
        expect(e.bytes, f.lengthSync());
      }
      expect(m.hashGlobal, calcularHashGlobal(m.entradas));
      expect(m.prefijoDeConfirmacion, m.hashGlobal.substring(0, 8));
    });

    test('un lote vacio da un manifiesto sin archivos', () async {
      final Manifiesto m = await calcularManifiesto(AlmacenCapturas(raiz));

      expect(m.entradas, isEmpty);
    });
  });

  group('exportar', () {
    test('genera un zip plano con todas las tomas y el manifiesto', () async {
      final AlmacenCapturas almacen = await almacenConTomas(raiz, 3);

      final ResultadoExportacion r = await exportarLote(almacen);

      expect(r.zip.existsSync(), isTrue);
      expect(p.dirname(r.zip.path), almacen.dirExportaciones.path);
      expect(
        p.basename(r.zip.path),
        'lote_${r.manifiesto.prefijoDeConfirmacion}.zip',
      );

      final Archive zip = ZipDecoder().decodeBytes(r.zip.readAsBytesSync());
      final Set<String> nombres = zip.files
          .map((ArchiveFile f) => f.name)
          .toSet();
      expect(nombres, hasLength(10));
      expect(nombres, contains(nombreManifiesto));
      expect(
        nombres.any((String n) => n.contains('/')),
        isFalse,
        reason: 'plano',
      );
    });

    test('cada archivo del zip es identico al del almacen', () async {
      final AlmacenCapturas almacen = await almacenConTomas(raiz, 3);

      final ResultadoExportacion r = await exportarLote(almacen);

      final Archive zip = ZipDecoder().decodeBytes(r.zip.readAsBytesSync());
      for (final ArchiveFile f in zip.files) {
        if (f.name == nombreManifiesto) continue;
        expect(
          f.content as List<int>,
          File(p.join(almacen.dirTomas.path, f.name)).readAsBytesSync(),
          reason: f.name,
        );
      }
    });

    test(
      'el manifiesto del zip coincide con lo que hay dentro, calculado aparte',
      () async {
        final AlmacenCapturas almacen = await almacenConTomas(raiz, 3);

        final ResultadoExportacion r = await exportarLote(almacen);

        final Archive zip = ZipDecoder().decodeBytes(r.zip.readAsBytesSync());
        final ArchiveFile manifiesto = zip.files.firstWhere(
          (ArchiveFile f) => f.name == nombreManifiesto,
        );
        final Map<String, Object?> json = jsonDecode(
          utf8.decode(manifiesto.content as List<int>),
        ) as Map<String, Object?>;
        expect(json['esquema'], versionEsquemaManifiesto);

        // Recalculo independiente, solo con lo que hay dentro del zip.
        final List<ArchiveFile> datos =
            zip.files
                .where((ArchiveFile f) => f.name != nombreManifiesto)
                .toList()
              ..sort(
                (ArchiveFile a, ArchiveFile b) => a.name.compareTo(b.name),
              );
        final StringBuffer lineas = StringBuffer();
        for (final ArchiveFile f in datos) {
          lineas.write(
            '${sha256.convert(f.content as List<int>)}  ${f.name}\n',
          );
        }
        expect(
          json['hash_global'],
          sha256.convert(utf8.encode(lineas.toString())).toString(),
        );

        final List<Object?> listados = json['archivos']! as List<Object?>;
        expect(listados, hasLength(9));
        for (final Object? e in listados) {
          final Map<String, Object?> entrada = e! as Map<String, Object?>;
          final ArchiveFile real = datos.firstWhere(
            (ArchiveFile f) => f.name == entrada['ruta'],
          );
          expect(
            entrada['sha256'],
            sha256.convert(real.content as List<int>).toString(),
          );
          expect(entrada['bytes'], (real.content as List<int>).length);
        }
      },
    );

    test('el manifiesto no se lista a si mismo', () async {
      final ResultadoExportacion r = await exportarLote(
        await almacenConTomas(raiz, 1),
      );

      expect(
        r.manifiesto.entradas.map((EntradaManifiesto e) => e.ruta),
        isNot(contains(nombreManifiesto)),
      );
    });

    test('exportar dos veces el mismo lote da el mismo hash', () async {
      final AlmacenCapturas almacen = await almacenConTomas(raiz, 2);

      final ResultadoExportacion a = await exportarLote(almacen);
      final ResultadoExportacion b = await exportarLote(almacen);

      expect(b.manifiesto.hashGlobal, a.manifiesto.hashGlobal);
      expect(b.zip.path, a.zip.path);
    });

    test('un lote vacio no se exporta', () async {
      await expectLater(
        exportarLote(AlmacenCapturas(raiz)),
        throwsA(isA<LoteVacio>()),
      );
    });

    test('un lote dañado no se exporta', () async {
      final AlmacenCapturas almacen = await almacenConTomas(raiz, 2);
      final File f = (await almacen.archivosDelLote()).firstWhere(
        (File x) => x.path.endsWith('_foto.jpg'),
      );
      final Uint8List bytes = f.readAsBytesSync();
      bytes[10] ^= 0xFF;
      f.writeAsBytesSync(bytes);

      await expectLater(
        exportarLote(almacen),
        throwsA(isA<IntegridadFallida>()),
      );
      expect(
        almacen.dirExportaciones.existsSync(),
        isFalse,
        reason: 'no deja un zip a medias',
      );
    });

    test('al agregar una toma el hash global cambia', () async {
      final AlmacenCapturas almacen = await almacenConTomas(raiz, 2);
      final String antes = (await calcularManifiesto(almacen)).hashGlobal;

      final CropperDePrueba cropper = CropperDePrueba();
      await ServicioCapturaPruebas(
        almacen: almacen,
        cropper: cropper,
      ).registrarToma(
        id: idDe(seudonimo: 'P5'),
        autorizacionFirmada: true,
        foto: fotoDePrueba(semilla: 9),
        celular: datosDelCelular(),
        parametrosCamara: const ParametrosDeCamara(),
        momento: DateTime.utc(2026),
      );

      expect((await calcularManifiesto(almacen)).hashGlobal, isNot(antes));
    });
  });

  group('borrar', () {
    test('con un texto que no es el prefijo no borra nada', () async {
      final AlmacenCapturas almacen = await almacenConTomas(raiz, 2);
      await exportarLote(almacen);
      final List<String> antes = await archivosBajo(raiz);

      await expectLater(
        borrarLote(almacen, confirmacion: '00000000'),
        throwsA(isA<ConfirmacionIncorrecta>()),
      );
      await expectLater(
        borrarLote(almacen, confirmacion: ''),
        throwsA(isA<ConfirmacionIncorrecta>()),
      );

      expect(await archivosBajo(raiz), antes);
    });

    test(
      'con el prefijo correcto borra las tomas y las exportaciones',
      () async {
        final AlmacenCapturas almacen = await almacenConTomas(raiz, 3);
        final ResultadoExportacion r = await exportarLote(almacen);

        await borrarLote(
          almacen,
          confirmacion: r.manifiesto.prefijoDeConfirmacion,
        );

        expect(await archivosBajo(raiz), isEmpty);
        expect(
          r.zip.existsSync(),
          isFalse,
          reason: 'el zip tambien tenia las fotos',
        );
      },
    );

    test('acepta mayusculas y espacios alrededor', () async {
      final AlmacenCapturas almacen = await almacenConTomas(raiz, 1);
      final Manifiesto m = await calcularManifiesto(almacen);

      await borrarLote(
        almacen,
        confirmacion: '  ${m.prefijoDeConfirmacion.toUpperCase()} ',
      );

      expect(await archivosBajo(raiz), isEmpty);
    });

    test('exige los 8 caracteres, no menos', () async {
      final AlmacenCapturas almacen = await almacenConTomas(raiz, 1);
      final Manifiesto m = await calcularManifiesto(almacen);

      await expectLater(
        borrarLote(almacen, confirmacion: m.hashGlobal.substring(0, 7)),
        throwsA(isA<ConfirmacionIncorrecta>()),
      );
      expect(await archivosBajo(raiz), isNotEmpty);
    });

    test(
      'si se tomo una foto despues de exportar, el prefijo viejo ya no vale',
      () async {
        final AlmacenCapturas almacen = await almacenConTomas(raiz, 2);
        final String prefijoViejo = (await exportarLote(almacen))
            .manifiesto
            .prefijoDeConfirmacion;
        await ServicioCapturaPruebas(
          almacen: almacen,
          cropper: CropperDePrueba(),
        ).registrarToma(
          id: idDe(seudonimo: 'P6'),
          autorizacionFirmada: true,
          foto: fotoDePrueba(semilla: 11),
          celular: datosDelCelular(),
          parametrosCamara: const ParametrosDeCamara(),
          momento: DateTime.utc(2026),
        );

        await expectLater(
          borrarLote(almacen, confirmacion: prefijoViejo),
          throwsA(isA<ConfirmacionIncorrecta>()),
        );

        expect(
          await almacen.listarTomas(),
          hasLength(3),
          reason: 'la toma nueva sigue ahi',
        );
      },
    );

    test('con el lote vacio no hay nada que confirmar', () async {
      await expectLater(
        borrarLote(AlmacenCapturas(raiz), confirmacion: ''),
        completes,
      );
    });

    test('si el borrado deja archivos, lo dice y los nombra', () async {
      final AlmacenCapturas almacen = await almacenConTomas(raiz, 1);
      final Manifiesto m = await calcularManifiesto(almacen);

      await expectLater(
        borrarLote(
          almacen,
          confirmacion: m.prefijoDeConfirmacion,
          borrarDirectorio: (Directory d) async {}, // un borrado que no borra
        ),
        throwsA(
          isA<BorradoIncompleto>().having(
            (BorradoIncompleto e) => e.restantes.length,
            'restantes',
            3,
          ),
        ),
      );
    });

    test(
      'tambien quita lo que sobra fuera de tomas/ y exportaciones/',
      () async {
        final AlmacenCapturas almacen = await almacenConTomas(raiz, 1);
        final Manifiesto m = await calcularManifiesto(almacen);
        File(p.join(raiz.path, 'huerfano.bin'))
            .writeAsBytesSync(<int>[1, 2, 3]);

        await expectLater(
          borrarLote(almacen, confirmacion: m.prefijoDeConfirmacion),
          throwsA(isA<BorradoIncompleto>()),
          reason: 'un archivo suelto en la raiz no se ignora en silencio',
        );
      },
    );

    test('despues de borrar se puede empezar un lote nuevo', () async {
      final AlmacenCapturas almacen = await almacenConTomas(raiz, 1);
      await borrarLote(
        almacen,
        confirmacion: (await calcularManifiesto(almacen)).prefijoDeConfirmacion,
      );

      await ServicioCapturaPruebas(
        almacen: almacen,
        cropper: CropperDePrueba(),
      ).registrarToma(
        id: idDe(),
        autorizacionFirmada: true,
        foto: fotoDePrueba(),
        celular: datosDelCelular(),
        parametrosCamara: const ParametrosDeCamara(),
        momento: DateTime.utc(2026),
      );

      expect(await almacen.listarTomas(), hasLength(1));
    });
  });
}
