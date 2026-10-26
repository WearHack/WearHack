/// Un elemento de la cola de captura (issue #11): una foto de prenda y en que
/// punto del camino va.
///
/// Solo hay tres estados **estables**, y son los unicos que se guardan en disco:
///
/// - [EstadoItem.porProcesar]: la foto esta guardada, falta quitarle el fondo y
///   clasificarla.
/// - [EstadoItem.porSubir]: ya esta procesada, falta subirla.
/// - [EstadoItem.fallida]: se agotaron los intentos. La foto original se
///   conserva para que la persona pueda reintentar o descartar.
///
/// "Procesando" y "subiendo" no existen como estado: si la app muere a mitad de
/// un proceso, al abrir de nuevo el elemento sigue en su estado estable y se
/// repite el paso. Es lo que hace que la cola sobreviva al cierre sin logica de
/// recuperacion aparte.
library;

import 'dart:typed_data';

import 'package:wearhack/core/vocabulario.dart';
import 'package:wearhack/platform/captura/contratos.dart';

enum EstadoItem { porProcesar, porSubir, fallida }

/// Los atributos que saca el pipeline, sin la imagen. La imagen vive en su
/// propio archivo: no tiene sentido llevar un PNG dentro de un JSON.
class DatosPrenda {
  const DatosPrenda({
    required this.tipo,
    required this.textura,
    required this.patron,
    required this.color,
    required this.categoriaColor,
  });

  factory DatosPrenda.dePrenda(PrendaClasificada p) => DatosPrenda(
    tipo: p.tipo,
    textura: p.textura,
    patron: p.patron,
    color: p.color,
    categoriaColor: p.categoriaColor,
  );

  factory DatosPrenda.fromJson(Map<String, Object?> json) => DatosPrenda(
    tipo: TipoPrenda.values.byName(json['tipo']! as String),
    textura: Textura.values.byName(json['textura']! as String),
    patron: Patron.values.byName(json['patron']! as String),
    color: ColorLab(
      l: (json['l']! as num).toDouble(),
      a: (json['a']! as num).toDouble(),
      b: (json['b']! as num).toDouble(),
    ),
    categoriaColor: CategoriaColor.values.byName(
      json['categoria_color']! as String,
    ),
  );

  final TipoPrenda tipo;
  final Textura textura;
  final Patron patron;
  final ColorLab color;
  final CategoriaColor categoriaColor;

  PrendaClasificada aPrenda(Uint8List imagenSinFondo) => PrendaClasificada(
    imagenSinFondo: imagenSinFondo,
    tipo: tipo,
    textura: textura,
    patron: patron,
    color: color,
    categoriaColor: categoriaColor,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'tipo': tipo.name,
    'textura': textura.name,
    'patron': patron.name,
    'l': color.l,
    'a': color.a,
    'b': color.b,
    'categoria_color': categoriaColor.name,
  };
}

class ItemCola {
  const ItemCola._({
    required this.id,
    required this.creadoEn,
    required this.estado,
    required this.intentos,
    required this.ultimoIntento,
    required this.ultimoError,
    required this.datos,
  });

  /// Una foto recien tomada.
  factory ItemCola.nuevo({required String id, required DateTime creadoEn}) =>
      ItemCola._(
        id: id,
        creadoEn: creadoEn,
        estado: EstadoItem.porProcesar,
        intentos: 0,
        ultimoIntento: null,
        ultimoError: null,
        datos: null,
      );

  factory ItemCola.fromJson(Map<String, Object?> json) {
    final Object? datos = json['datos'];
    final Object? ultimo = json['ultimo_intento'];
    return ItemCola._(
      id: json['id']! as String,
      creadoEn: DateTime.parse(json['creado_en']! as String),
      estado: EstadoItem.values.byName(json['estado']! as String),
      intentos: json['intentos']! as int,
      ultimoIntento: ultimo == null ? null : DateTime.parse(ultimo as String),
      ultimoError: json['ultimo_error'] as String?,
      datos: datos == null
          ? null
          : DatosPrenda.fromJson((datos as Map<Object?, Object?>).cast()),
    );
  }

  /// Identificador generado en el telefono. Tambien es la **llave de
  /// idempotencia** de la subida: si la app muere justo despues de subir y antes
  /// de guardarlo, al reintentar el servidor debe reconocer el mismo id.
  final String id;

  final DateTime creadoEn;
  final EstadoItem estado;

  /// Intentos fallidos del paso actual. Los fallos de red no cuentan aqui:
  /// sin conexion no es culpa de la foto.
  final int intentos;

  final DateTime? ultimoIntento;
  final String? ultimoError;

  /// Presente desde que la foto esta procesada.
  final DatosPrenda? datos;

  bool get pendiente =>
      estado == EstadoItem.porProcesar || estado == EstadoItem.porSubir;

  /// La foto salio bien del pipeline.
  ItemCola procesado(DatosPrenda datos) => ItemCola._(
    id: id,
    creadoEn: creadoEn,
    estado: EstadoItem.porSubir,
    intentos: 0,
    ultimoIntento: null,
    ultimoError: null,
    datos: datos,
  );

  /// Un paso fallo. Si [definitivo], se agotaron los intentos.
  ItemCola conFallo({
    required DateTime ahora,
    required String error,
    required bool definitivo,
  }) => ItemCola._(
    id: id,
    creadoEn: creadoEn,
    estado: definitivo ? EstadoItem.fallida : estado,
    intentos: intentos + 1,
    ultimoIntento: ahora,
    ultimoError: error,
    datos: datos,
  );

  /// Vuelve a empezar desde el paso que le faltaba.
  ItemCola reintentable() => ItemCola._(
    id: id,
    creadoEn: creadoEn,
    estado: datos == null ? EstadoItem.porProcesar : EstadoItem.porSubir,
    intentos: 0,
    ultimoIntento: null,
    ultimoError: null,
    datos: datos,
  );

  /// El PNG procesado se perdio: hay que volver a procesar la original.
  ItemCola aReprocesar() => ItemCola._(
    id: id,
    creadoEn: creadoEn,
    estado: EstadoItem.porProcesar,
    intentos: 0,
    ultimoIntento: null,
    ultimoError: null,
    datos: null,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'creado_en': creadoEn.toUtc().toIso8601String(),
    'estado': estado.name,
    'intentos': intentos,
    'ultimo_intento': ultimoIntento?.toUtc().toIso8601String(),
    'ultimo_error': ultimoError,
    'datos': datos?.toJson(),
  };
}
