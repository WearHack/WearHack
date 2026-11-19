/// Los ajustes de categoria de color que decide el Core (#58).
///
/// `GET /api/v1/closet/colores/ajustes` devuelve los bloques ISCC-NBS que
/// cambiaron de categoria por las correcciones de los usuarios. La app los
/// aplica sobre la tabla que trae ([TablaIsccNbs.conAjustes]).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:wearhack/core/color/categoria_color.dart';
import 'package:wearhack/core/vocabulario.dart';
import 'package:wearhack/features/cuenta/cliente_usuarios.dart';

class ClienteAjustesColor {
  ClienteAjustesColor({
    required this.cliente,
    required this.base,
    required this.token,
  });

  final http.Client cliente;

  /// Raiz del Core, sin barra final.
  final String base;

  /// El token de acceso de la sesion actual.
  final Future<String> Function() token;

  /// Bloque -> categoria. Una categoria que esta version de la app no conoce se
  /// salta: mejor la de la tabla que fallar la captura.
  Future<Map<int, CategoriaColor>> ajustes() async {
    final http.Response respuesta = await cliente.get(
      Uri.parse('$base/api/v1/closet/colores/ajustes'),
      headers: <String, String>{'Authorization': 'Bearer ${await token()}'},
    );
    if (respuesta.statusCode != 200) {
      throw ErrorDelCore(
        respuesta.statusCode,
        'No se pudieron leer los ajustes de color',
      );
    }
    final Map<String, Object?> json =
        jsonDecode(utf8.decode(respuesta.bodyBytes)) as Map<String, Object?>;
    final Map<int, CategoriaColor> ajustes = <int, CategoriaColor>{};
    for (final Object? a in json['ajustes']! as List<Object?>) {
      final Map<String, Object?> ajuste = a! as Map<String, Object?>;
      try {
        ajustes[(ajuste['bloque']! as num).toInt()] =
            CategoriaColor.desdeCodigo(ajuste['categoria']! as String);
      } on FormatException {
        continue;
      }
    }
    return ajustes;
  }
}
