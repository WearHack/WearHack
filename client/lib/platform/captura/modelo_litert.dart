import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Abre el asset desde un archivo privado y lo borra al cerrar el intérprete.
Future<T> conArchivoLiteRT<T>(
  String asset,
  Future<T> Function(String ruta) ejecutar,
) async {
  final ByteData datos = await rootBundle.load(asset);
  final Directory base = await getTemporaryDirectory();
  final Directory temporal = await base.createTemp('modelo_prenda_');
  try {
    final File archivo = File('${temporal.path}/modelo.tflite');
    await archivo.writeAsBytes(
      datos.buffer.asUint8List(datos.offsetInBytes, datos.lengthInBytes),
    );
    return await ejecutar(archivo.path);
  } finally {
    await temporal.delete(recursive: true);
  }
}
