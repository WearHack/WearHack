/// El almacen de la cola en disco (issue #11). Solo movil.
///
/// Escribe en el directorio de **soporte de la aplicacion**, que es privado de
/// la app: ni la galeria ni otras apps lo ven. Nada va a `Pictures`, `DCIM` ni
/// al almacenamiento compartido.
///
/// Este archivo importa `dart:io`, asi que no debe alcanzarse desde la build de
/// web. Hoy nadie lo importa desde `lib/`: se conecta con la pantalla de captura
/// de prendas, detras del import condicional, cuando exista.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wearhack/features/closet/captura/almacen_cola.dart';
import 'package:wearhack/features/closet/captura/item_cola.dart';

class AlmacenColaArchivos implements AlmacenCola {
  AlmacenColaArchivos(this._carpeta);

  /// La carpeta de la cola dentro del soporte privado de la app.
  static Future<AlmacenColaArchivos> enSoporteDeLaApp() async {
    final Directory base = await getApplicationSupportDirectory();
    final Directory carpeta = Directory(p.join(base.path, 'cola_captura'));
    await carpeta.create(recursive: true);
    return AlmacenColaArchivos(carpeta);
  }

  final Directory _carpeta;

  static const int _versionIndice = 1;
  static final RegExp _idValido = RegExp(r'^[A-Za-z0-9_-]+$');

  File get _indice => File(p.join(_carpeta.path, 'indice.json'));

  /// Los ids los genera la app, pero se validan igual: un id con `..` o `/`
  /// escribiria fuera de la carpeta.
  File _archivo(String id, String extension) {
    if (!_idValido.hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'Solo letras, numeros, _ y -');
    }
    return File(p.join(_carpeta.path, '$id.$extension'));
  }

  @override
  Future<List<ItemCola>> cargar() async {
    final File indice = _indice;
    if (!await indice.exists()) return <ItemCola>[];
    try {
      final Object? json = jsonDecode(await indice.readAsString());
      if (json is! Map<String, Object?> || json['version'] != _versionIndice) {
        throw const FormatException('Version de indice desconocida');
      }
      return <ItemCola>[
        for (final Object? e in json['items']! as List<Object?>)
          ItemCola.fromJson((e! as Map<Object?, Object?>).cast()),
      ];
    } on Object {
      // Un indice ilegible no se borra: se aparta para poder mirarlo. Las fotos
      // originales siguen en la carpeta y se pueden recuperar a mano.
      final String aparte = p.join(
        _carpeta.path,
        'indice.corrupto-${DateTime.now().millisecondsSinceEpoch}.json',
      );
      await indice.rename(aparte);
      return <ItemCola>[];
    }
  }

  @override
  Future<void> guardarIndice(List<ItemCola> items) async {
    final String texto = jsonEncode(<String, Object?>{
      'version': _versionIndice,
      'items': <Object?>[for (final ItemCola i in items) i.toJson()],
    });
    // Se escribe a un temporal y se renombra encima: o queda el indice viejo o
    // el nuevo, nunca uno a medias.
    final File temporal = File('${_indice.path}.tmp');
    await temporal.writeAsString(texto, flush: true);
    await temporal.rename(_indice.path);
  }

  @override
  Future<void> guardarOriginal(String id, Uint8List bytes) async {
    await _archivo(id, 'orig').writeAsBytes(bytes, flush: true);
  }

  @override
  Future<Uint8List> leerOriginal(String id) => _leer(id, 'orig', 'la original');

  @override
  Future<void> guardarProcesada(String id, Uint8List png) async {
    await _archivo(id, 'png').writeAsBytes(png, flush: true);
  }

  @override
  Future<Uint8List> leerProcesada(String id) =>
      _leer(id, 'png', 'la procesada');

  Future<Uint8List> _leer(String id, String extension, String cual) async {
    final File f = _archivo(id, extension);
    if (!await f.exists()) throw ArchivoDeColaFaltante(id, cual);
    return f.readAsBytes();
  }

  @override
  Future<void> borrarArchivos(String id) async {
    for (final String extension in <String>['orig', 'png']) {
      final File f = _archivo(id, extension);
      // Si ya no estaba, no hay nada que hacer.
      if (await f.exists()) await f.delete();
    }
  }
}
