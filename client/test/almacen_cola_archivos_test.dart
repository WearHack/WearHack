/// El almacen de la cola en disco (issue #11), sobre una carpeta temporal real.
///
/// No prueba que sea el directorio privado de la app: eso es
/// `getApplicationSupportDirectory`, que solo existe en un telefono.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wearhack/features/closet/captura/almacen_cola.dart';
import 'package:wearhack/features/closet/captura/cola_captura.dart';
import 'package:wearhack/features/closet/captura/item_cola.dart';
import 'package:wearhack/platform/captura/almacen_cola_archivos.dart';

import 'helpers/cola_helpers.dart';

void main() {
  late Directory carpeta;
  late AlmacenColaArchivos almacen;

  setUp(() {
    carpeta = Directory.systemTemp.createTempSync('cola_captura_test_');
    almacen = AlmacenColaArchivos(carpeta);
  });

  tearDown(() {
    if (carpeta.existsSync()) carpeta.deleteSync(recursive: true);
  });

  List<String> nombres() => <String>[
    for (final FileSystemEntity e in carpeta.listSync()) p.basename(e.path),
  ]..sort();

  test('sin indice, la cola arranca vacia', () async {
    expect(await almacen.cargar(), isEmpty);
  });

  test('el indice vuelve igual que se guardo', () async {
    final List<ItemCola> items = <ItemCola>[
      ItemCola.nuevo(id: 'a1', creadoEn: DateTime.utc(2026, 10, 26)),
      ItemCola.nuevo(
        id: 'b2',
        creadoEn: DateTime.utc(2026, 10, 26, 1),
      ).procesado(DatosPrenda.dePrenda(prendaDeEjemplo())),
    ];

    await almacen.guardarIndice(items);
    final List<ItemCola> leidos = await almacen.cargar();

    expect(leidos.map((ItemCola i) => i.id), <String>['a1', 'b2']);
    expect(leidos[0].estado, EstadoItem.porProcesar);
    expect(leidos[1].estado, EstadoItem.porSubir);
    expect(leidos[1].datos!.color.a, 10);
  });

  test('guardar el indice no deja el temporal', () async {
    await almacen.guardarIndice(<ItemCola>[]);
    await almacen.guardarIndice(<ItemCola>[]);

    expect(nombres(), <String>['indice.json']);
  });

  test('guarda, lee y borra las fotos', () async {
    final Uint8List bytes = Uint8List.fromList(<int>[9, 8, 7]);
    await almacen.guardarOriginal('a1', bytes);
    await almacen.guardarProcesada('a1', Uint8List.fromList(<int>[1]));

    expect(await almacen.leerOriginal('a1'), bytes);
    expect(await almacen.leerProcesada('a1'), <int>[1]);

    await almacen.borrarArchivos('a1');

    expect(nombres(), isEmpty);
  });

  test('borrar lo que ya no esta no falla', () async {
    await almacen.borrarArchivos('no_existe');
  });

  test('leer lo que falta lanza un error con nombre', () async {
    await expectLater(
      almacen.leerOriginal('a1'),
      throwsA(isA<ArchivoDeColaFaltante>()),
    );
  });

  test('un id con rutas no escribe fuera de la carpeta', () async {
    for (final String malo in <String>['../fuera', 'a/b', r'a\b', '', 'a.b']) {
      await expectLater(
        almacen.guardarOriginal(malo, Uint8List(1)),
        throwsArgumentError,
        reason: 'id: "$malo"',
      );
    }
    expect(nombres(), isEmpty);
    expect(
      File(p.join(carpeta.parent.path, 'fuera.orig')).existsSync(),
      isFalse,
    );
  });

  test('un indice ilegible se aparta y no se pierde', () async {
    File(p.join(carpeta.path, 'indice.json')).writeAsStringSync('{ esto no es');
    await almacen.guardarOriginal('a1', Uint8List(1));

    expect(await almacen.cargar(), isEmpty);

    final List<String> n = nombres();
    expect(n, contains('a1.orig'));
    expect(
      n.where((String x) => x.startsWith('indice.corrupto-')),
      hasLength(1),
    );
    expect(n, isNot(contains('indice.json')));
  });

  test('un indice de otra version tambien se aparta', () async {
    File(p.join(carpeta.path, 'indice.json'))
        .writeAsStringSync('{"version": 99, "items": []}');

    expect(await almacen.cargar(), isEmpty);
    expect(
      nombres().where((String x) => x.startsWith('indice.corrupto-')),
      hasLength(1),
    );
  });

  test(
    'la cola completa sobre archivos reales: encola, procesa, sube y limpia',
    () async {
      final ProcesadorFalso procesador = ProcesadorFalso();
      final SubidorFalso subidor = SubidorFalso();
      final ColaCaptura cola = await ColaCaptura.abrir(
        almacen: almacen,
        procesador: procesador,
        subidor: subidor,
        automatica: false,
      );

      final String id = await cola.encolar(foto(1));
      // Mientras espera, hay una foto y el indice, nada mas.
      expect(nombres(), unorderedEquals(<String>['$id.orig', 'indice.json']));

      await cola.ronda();

      expect(subidor.subidos, <String>[id]);
      // Subida confirmada: queda solo el indice, vacio.
      expect(nombres(), <String>['indice.json']);
      expect(await almacen.cargar(), isEmpty);
    },
  );

  test('cerrar y reabrir sobre archivos reales no pierde la foto', () async {
    final SubidorFalso subidor = SubidorFalso()..guion.add(const SinConexion());
    final ColaCaptura primera = await ColaCaptura.abrir(
      almacen: almacen,
      procesador: ProcesadorFalso(),
      subidor: subidor,
      automatica: false,
    );
    final String id = await primera.encolar(foto(1));
    await primera.ronda(); // procesada, sin red para subirla
    expect(
      nombres(),
      unorderedEquals(<String>['$id.orig', '$id.png', 'indice.json']),
    );

    final ColaCaptura segunda = await ColaCaptura.abrir(
      almacen: AlmacenColaArchivos(carpeta),
      procesador: ProcesadorFalso(),
      subidor: subidor,
      automatica: false,
    );

    expect(segunda.items.single.estado, EstadoItem.porSubir);
    expect(await segunda.ronda(), isNull);
    expect(subidor.subidos, <String>[id]);
    expect(nombres(), <String>['indice.json']);
  });
}
