/// El lote: manifiesto con hash global, exportacion a zip y borrado con
/// confirmacion.
///
/// El flujo de la spec (3.5): **Exportar** genera un zip con las tomas y un
/// `manifiesto.json`; en el computador `importar_lote.py` verifica los hashes y
/// muestra el hash global; **Borrar** solo se habilita si el operador escribe en
/// la app los 8 primeros caracteres de ese hash.
///
/// El hash global se calcula siempre sobre el estado actual del almacen, no
/// sobre el ultimo zip. Asi, una toma tomada despues de exportar cambia el hash,
/// el prefijo que se vio en el computador deja de valer, y el borrado se niega:
/// no se pierde lo que nunca se importo.
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:wearhack/features/captura_pruebas/almacen_capturas.dart';
import 'package:wearhack/features/captura_pruebas/modelos.dart';

const int versionEsquemaManifiesto = 1;
const String nombreManifiesto = 'manifiesto.json';

class EntradaManifiesto {
  const EntradaManifiesto({
    required this.ruta,
    required this.sha256,
    required this.bytes,
  });

  /// Nombre del archivo dentro del zip. El zip es plano: sin carpetas.
  final String ruta;
  final String sha256;
  final int bytes;
}

class Manifiesto {
  const Manifiesto({required this.entradas, required this.hashGlobal});

  final List<EntradaManifiesto> entradas;

  /// Ver [calcularHashGlobal].
  final String hashGlobal;

  Map<String, Object?> toJson() => <String, Object?>{
    'esquema': versionEsquemaManifiesto,
    'archivos': <Object?>[
      for (final EntradaManifiesto e in entradas)
        <String, Object?>{'ruta': e.ruta, 'sha256': e.sha256, 'bytes': e.bytes},
    ],
    'hash_global': hashGlobal,
  };

  /// Los 8 primeros caracteres: lo que el operador teclea para confirmar.
  String get prefijoDeConfirmacion => hashGlobal.substring(0, 8);
}

/// SHA-256 del texto formado por una linea `"<sha256>  <ruta>\n"` por archivo
/// (dos espacios, como `sha256sum`), ordenadas por ruta en orden ordinal.
///
/// El manifiesto no se cuenta a si mismo. `importar_lote.py` calcula lo mismo.
String calcularHashGlobal(List<EntradaManifiesto> entradas) {
  final List<EntradaManifiesto> orden = List<EntradaManifiesto>.of(entradas)
    ..sort(
      (EntradaManifiesto a, EntradaManifiesto b) => a.ruta.compareTo(b.ruta),
    );
  final StringBuffer texto = StringBuffer();
  for (final EntradaManifiesto e in orden) {
    texto.write('${e.sha256}  ${e.ruta}\n');
  }
  return sha256.convert(utf8.encode(texto.toString())).toString();
}

/// Manifiesto del estado actual de `tomas/`.
Future<Manifiesto> calcularManifiesto(AlmacenCapturas almacen) async {
  final List<EntradaManifiesto> entradas = <EntradaManifiesto>[
    for (final File f in await almacen.archivosDelLote())
      EntradaManifiesto(
        ruta: p.basename(f.path),
        sha256: (await sha256.bind(f.openRead()).first).toString(),
        bytes: await f.length(),
      ),
  ];
  return Manifiesto(
    entradas: entradas,
    hashGlobal: calcularHashGlobal(entradas),
  );
}

class LoteVacio implements Exception {
  const LoteVacio();

  @override
  String toString() => 'LoteVacio: no hay tomas que exportar';
}

class IntegridadFallida implements Exception {
  const IntegridadFallida(this.problemas);

  final List<String> problemas;

  @override
  String toString() => 'IntegridadFallida: ${problemas.join('; ')}';
}

class ResultadoExportacion {
  const ResultadoExportacion({required this.zip, required this.manifiesto});

  final File zip;
  final Manifiesto manifiesto;
}

/// Genera el zip del lote en `exportaciones/`.
///
/// Se niega a exportar un lote vacio ([LoteVacio]) o dañado
/// ([IntegridadFallida]). El zip se escribe sin compresion: JPEG y PNG ya estan
/// comprimidos y comprimirlos de nuevo solo gasta tiempo.
Future<ResultadoExportacion> exportarLote(AlmacenCapturas almacen) async {
  final List<IdToma> tomas = await almacen.listarTomas();
  final List<File> archivos = await almacen.archivosDelLote();
  if (tomas.isEmpty && archivos.isEmpty) throw const LoteVacio();

  final List<String> problemas = await almacen.verificarIntegridad();
  if (problemas.isNotEmpty) throw IntegridadFallida(problemas);

  final Manifiesto manifiesto = await calcularManifiesto(almacen);
  await almacen.dirExportaciones.create(recursive: true);
  final File zip = File(
    p.join(
      almacen.dirExportaciones.path,
      'lote_${manifiesto.prefijoDeConfirmacion}.zip',
    ),
  );
  if (await zip.exists()) await zip.delete();

  final ZipFileEncoder encoder = ZipFileEncoder()..create(zip.path, level: 0);
  try {
    for (final File f in archivos) {
      await encoder.addFile(f, p.basename(f.path), 0);
    }
    encoder.addArchiveFile(
      ArchiveFile.bytes(
        nombreManifiesto,
        utf8.encode(
          '${const JsonEncoder.withIndent('  ').convert(manifiesto.toJson())}\n',
        ),
      ),
    );
  } finally {
    await encoder.close();
  }
  return ResultadoExportacion(zip: zip, manifiesto: manifiesto);
}

/// El texto de confirmacion no es el prefijo del hash global actual.
class ConfirmacionIncorrecta implements Exception {
  const ConfirmacionIncorrecta();

  @override
  String toString() =>
      'ConfirmacionIncorrecta: no coincide con los 8 primeros caracteres del '
      'hash global actual. Si tomaste fotos despues de exportar, vuelve a '
      'exportar e importar el lote.';
}

/// El borrado termino y quedaron archivos del lote.
class BorradoIncompleto implements Exception {
  const BorradoIncompleto(this.restantes);

  final List<String> restantes;

  @override
  String toString() =>
      'BorradoIncompleto: quedan ${restantes.length} archivos: '
      '${restantes.join(', ')}';
}

/// Borra todas las tomas y las exportaciones, y comprueba que no quede nada.
///
/// Exige que [confirmacion] sean los 8 primeros caracteres del hash global
/// **actual** del lote (mayusculas y espacios no importan). Con el lote vacio no
/// hay nada que confirmar y no hace nada.
///
/// [borrarDirectorio] existe para las pruebas.
Future<void> borrarLote(
  AlmacenCapturas almacen, {
  required String confirmacion,
  Future<void> Function(Directory) borrarDirectorio = _borrarRecursivo,
}) async {
  if ((await almacen.archivosDelLote()).isNotEmpty) {
    final Manifiesto manifiesto = await calcularManifiesto(almacen);
    if (confirmacion.trim().toLowerCase() != manifiesto.prefijoDeConfirmacion) {
      throw const ConfirmacionIncorrecta();
    }
  }

  for (final Directory d in <Directory>[
    almacen.dirTomas,
    almacen.dirExportaciones,
  ]) {
    if (await d.exists()) await borrarDirectorio(d);
  }

  final List<String> restantes = <String>[
    if (await almacen.raiz.exists())
      await for (final FileSystemEntity e in almacen.raiz.list(recursive: true))
        if (e is File) p.relative(e.path, from: almacen.raiz.path),
  ];
  if (restantes.isNotEmpty) throw BorradoIncompleto(restantes);
}

Future<void> _borrarRecursivo(Directory d) => d.delete(recursive: true);
