/// Donde la cola guarda sus cosas (issue #11).
///
/// Es una interfaz para que la logica de la cola se pruebe sin disco. La
/// implementacion real escribe en el almacenamiento **privado** de la app, nunca
/// en la galeria (`lib/platform/captura/almacen_cola_archivos.dart`).
///
/// Orden de escritura que la cola respeta, para que una muerte en cualquier
/// punto no pierda una foto:
///
/// - Encolar: primero la foto, despues el indice. Una foto sin indice es un
///   huerfano inofensivo; un indice sin foto seria una foto perdida.
/// - Subida confirmada: primero el indice sin ese elemento, despues los
///   archivos. Al reves, un cierre en medio dejaria un elemento "por subir"
///   sin su imagen.
library;

import 'dart:typed_data';

import 'package:wearhack/features/closet/captura/item_cola.dart';

abstract interface class AlmacenCola {
  /// El indice guardado, o una lista vacia si no hay.
  Future<List<ItemCola>> cargar();

  /// Reemplaza el indice completo. Debe ser atomico: o queda el anterior o
  /// queda el nuevo, nunca uno a medias.
  Future<void> guardarIndice(List<ItemCola> items);

  /// La foto tal como salio de la camara.
  Future<void> guardarOriginal(String id, Uint8List bytes);
  Future<Uint8List> leerOriginal(String id);

  /// La prenda ya sin fondo, lista para subir.
  Future<void> guardarProcesada(String id, Uint8List png);
  Future<Uint8List> leerProcesada(String id);

  /// Borra la original y la procesada. No falla si alguna ya no existe.
  Future<void> borrarArchivos(String id);
}

/// Falta un archivo que el indice daba por existente.
class ArchivoDeColaFaltante implements Exception {
  const ArchivoDeColaFaltante(this.id, this.cual);

  final String id;
  final String cual;

  @override
  String toString() => 'ArchivoDeColaFaltante: no esta $cual de $id';
}
