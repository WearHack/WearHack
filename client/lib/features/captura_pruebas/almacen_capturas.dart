/// Donde viven las tomas de calibracion, dentro del almacenamiento privado de la
/// app y nunca en la galeria ni en el repositorio.
///
/// Disposicion bajo `raiz`:
///
///   tomas/            las tomas: `<base>_foto.jpg`, `<base>_recorte.png`, `<base>.json`
///   exportaciones/    los zip generados, hasta que se borre el lote
///
/// Una toma "existe" cuando existe su `.json`, que se escribe **el ultimo**: si
/// la app se cierra a medias, los archivos huerfanos no cuentan como toma y la
/// verificacion de integridad los senala.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:wearhack/core/recorte/recortador_facial.dart';
import 'package:wearhack/features/captura_pruebas/metadatos.dart';
import 'package:wearhack/features/captura_pruebas/modelos.dart';

/// La carpeta del almacen esta dentro de un repositorio git. Las fotos de
/// calibracion no pueden acabar ahi.
class AlmacenDentroDelRepositorio implements Exception {
  const AlmacenDentroDelRepositorio(this.ruta, this.repositorio);

  final String ruta;
  final String repositorio;

  @override
  String toString() =>
      'AlmacenDentroDelRepositorio: $ruta esta dentro del repositorio '
      '$repositorio. Las fotos de calibracion nunca van en un repositorio.';
}

class TomaYaExiste implements Exception {
  const TomaYaExiste(this.id);

  final IdToma id;

  @override
  String toString() => 'TomaYaExiste: ya hay una toma $id (usa reemplazar)';
}

class AlmacenCapturas {
  /// Lanza [AlmacenDentroDelRepositorio] si [raiz] esta dentro de un
  /// repositorio git (la ruta o cualquiera de sus carpetas superiores tiene
  /// `.git`).
  AlmacenCapturas(Directory raiz) : raiz = Directory(p.absolute(raiz.path)) {
    _rechazarSiEstaEnUnRepositorio(this.raiz.path);
  }

  final Directory raiz;

  Directory get dirTomas => Directory(p.join(raiz.path, 'tomas'));
  Directory get dirExportaciones =>
      Directory(p.join(raiz.path, 'exportaciones'));

  static const Set<String> _extensionesDeFoto = <String>{'jpg', 'heic'};

  /// Guarda una toma. La foto se escribe **tal como la entrego la camara**, sin
  /// recodificar, para que conserve su perfil de color. El recorte es el PNG
  /// que produjo [RecortadorFacial].
  ///
  /// Si ya hay una toma con ese [id] y [reemplazar] es `false`, lanza
  /// [TomaYaExiste]. Con `true` la nueva reemplaza a la anterior.
  Future<MetadatosToma> guardarToma({
    required IdToma id,
    required Uint8List foto,
    required String extensionFoto,
    required RecorteFacial recorte,
    required DatosDelCelular celular,
    required ParametrosDeCamara parametrosCamara,
    required DateTime momento,
    bool reemplazar = false,
  }) async {
    final String ext = extensionFoto.toLowerCase().replaceFirst('.', '');
    if (!_extensionesDeFoto.contains(ext)) {
      throw ArgumentError.value(
        extensionFoto,
        'extensionFoto',
        'Debe ser jpg o heic',
      );
    }
    if (celular.codigo != id.celular) {
      throw ArgumentError(
        'El celular de los datos (${celular.codigo.codigo}) no es el de la toma '
        '(${id.celular.codigo})',
      );
    }

    final bool existe = await File(_rutaJson(id)).exists();
    if (existe && !reemplazar) throw TomaYaExiste(id);

    await dirTomas.create(recursive: true);
    if (existe) await _borrarArchivosDe(id);

    final String nombreFoto = '${id.nombreBase}_foto.$ext';
    final String nombreRecorte = '${id.nombreBase}_recorte.png';
    final MetadatosToma metadatos = MetadatosToma(
      id: id,
      fechaHora: momento,
      celular: celular,
      parametrosCamara: parametrosCamara,
      rostroBbox: <num>[
        recorte.caja.left,
        recorte.caja.top,
        recorte.caja.right,
        recorte.caja.bottom,
      ],
      anchoRostroPx: recorte.anchoRostroPx,
      perfilFoto: recorte.perfilOrigen,
      perfilRecorte: recorte.perfilRecorte,
      archivoFoto: nombreFoto,
      archivoRecorte: nombreRecorte,
      sha256Foto: sha256.convert(foto).toString(),
      sha256Recorte: sha256.convert(recorte.png).toString(),
    );
    final Map<String, Object?> json = metadatos.toJson();
    final List<String> problemas = validarMetadatos(json);
    if (problemas.isNotEmpty) {
      throw StateError('Metadatos invalidos: ${problemas.join('; ')}');
    }

    await _escribir(p.join(dirTomas.path, nombreFoto), foto);
    await _escribir(p.join(dirTomas.path, nombreRecorte), recorte.png);
    await _escribir(
      _rutaJson(id),
      utf8.encode('${const JsonEncoder.withIndent('  ').convert(json)}\n'),
    );
    return metadatos;
  }

  /// Las tomas guardadas, ordenadas por nombre.
  Future<List<IdToma>> listarTomas() async {
    if (!await dirTomas.exists()) return <IdToma>[];
    final List<IdToma> ids = <IdToma>[];
    await for (final FileSystemEntity e in dirTomas.list()) {
      if (e is! File || p.extension(e.path) != '.json') continue;
      final IdToma? id = IdToma.desdeNombreBase(
        p.basenameWithoutExtension(e.path),
      );
      if (id != null) ids.add(id);
    }
    ids.sort((IdToma a, IdToma b) => a.nombreBase.compareTo(b.nombreBase));
    return ids;
  }

  Future<Map<String, Object?>> leerMetadatos(IdToma id) async =>
      jsonDecode(await File(_rutaJson(id)).readAsString())
          as Map<String, Object?>;

  /// Todos los archivos de `tomas/`, ordenados por nombre.
  Future<List<File>> archivosDelLote() async {
    if (!await dirTomas.exists()) return <File>[];
    final List<File> archivos = <File>[
      await for (final FileSystemEntity e in dirTomas.list())
        if (e is File) e,
    ];
    archivos.sort(
      (File a, File b) => p.basename(a.path).compareTo(p.basename(b.path)),
    );
    return archivos;
  }

  /// Revisa que el lote este sano: cada JSON valida contra el esquema, sus dos
  /// archivos existen y coinciden con el SHA-256 declarado, y no sobra ningun
  /// archivo. Devuelve una frase por problema; vacio si esta sano.
  Future<List<String>> verificarIntegridad() async {
    final List<String> problemas = <String>[];
    final Set<String> esperados = <String>{};

    for (final IdToma id in await listarTomas()) {
      final Map<String, Object?> json;
      try {
        json = await leerMetadatos(id);
      } on FormatException catch (e) {
        problemas.add(
          '${id.nombreBase}.json no es un JSON valido: ${e.message}',
        );
        continue;
      }
      esperados.add('${id.nombreBase}.json');
      for (final String m in validarMetadatos(json)) {
        problemas.add('${id.nombreBase}.json: $m');
      }
      final Object? archivos = json['archivos'];
      if (archivos is! Map<String, Object?>) continue;
      final Object? sha = archivos['sha256'];
      for (final String clave in <String>['foto', 'recorte']) {
        final Object? nombre = archivos[clave];
        if (nombre is! String || sha is! Map<String, Object?>) continue;
        esperados.add(nombre);
        final File f = File(p.join(dirTomas.path, nombre));
        if (!await f.exists()) {
          problemas.add('${id.nombreBase}: falta $nombre');
        } else if ((await sha256.bind(f.openRead()).first).toString() !=
            sha[clave]) {
          problemas.add('${id.nombreBase}: $nombre no coincide con su SHA-256');
        }
      }
    }

    for (final File f in await archivosDelLote()) {
      if (!esperados.contains(p.basename(f.path))) {
        problemas.add('sobra el archivo ${p.basename(f.path)}');
      }
    }
    return problemas;
  }

  String _rutaJson(IdToma id) => p.join(dirTomas.path, '${id.nombreBase}.json');

  Future<void> _borrarArchivosDe(IdToma id) async {
    // El JSON primero: a medio borrar, la toma deja de existir.
    final File json = File(_rutaJson(id));
    if (await json.exists()) await json.delete();
    await for (final FileSystemEntity e in dirTomas.list()) {
      final String nombre = p.basename(e.path);
      if (e is File &&
          (nombre.startsWith('${id.nombreBase}_foto.') ||
              nombre == '${id.nombreBase}_recorte.png')) {
        await e.delete();
      }
    }
  }

  /// Escribe a un temporal y renombra, para no dejar un archivo a medias.
  Future<void> _escribir(String destino, List<int> bytes) async {
    final File temporal = File('$destino.tmp');
    await temporal.writeAsBytes(bytes, flush: true);
    await temporal.rename(destino);
  }

  static void _rechazarSiEstaEnUnRepositorio(String ruta) {
    String actual = _resolver(ruta);
    while (true) {
      if (FileSystemEntity.typeSync(p.join(actual, '.git')) !=
          FileSystemEntityType.notFound) {
        throw AlmacenDentroDelRepositorio(ruta, actual);
      }
      final String padre = p.dirname(actual);
      if (padre == actual) return;
      actual = padre;
    }
  }

  /// Resuelve enlaces simbolicos del tramo que ya existe, para que un enlace no
  /// esconda que la carpeta esta dentro de un repositorio.
  static String _resolver(String ruta) {
    final List<String> pendiente = <String>[];
    String actual = ruta;
    while (!Directory(actual).existsSync()) {
      final String padre = p.dirname(actual);
      if (padre == actual) return ruta;
      pendiente.insert(0, p.basename(actual));
      actual = padre;
    }
    return p.joinAll(<String>[
      Directory(actual).resolveSymbolicLinksSync(),
      ...pendiente,
    ]);
  }
}
