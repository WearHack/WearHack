/// La conexion con el Core para todo lo que cuelga de `/api/v1/usuarios/me`.
///
/// El consentimiento y el analisis de colorimetria hablan con el mismo sitio, con
/// el mismo token y con los mismos errores, asi que comparten esto. El contrato
/// esta en `docs/api-usuarios.md`.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:wearhack/features/cuenta/cliente_usuarios.dart';

class ConexionCore {
  ConexionCore({
    required this.cliente,
    required this.base,
    required this.token,
  });

  final http.Client cliente;

  /// Raiz del Core, sin barra final.
  final String base;

  /// El token de acceso de la sesion actual. Nunca el de identidad.
  final Future<String> Function() token;

  Uri uri(String ruta) => Uri.parse('$base/api/v1/usuarios/me$ruta');

  Future<Map<String, String>> cabeceras({String? tipo}) async =>
      <String, String>{
        'Authorization': 'Bearer ${await token()}',
        'Content-Type': ?tipo,
      };

  /// Deja pasar las respuestas 2xx y las de [toleradas]; con cualquier otra
  /// lanza [ErrorDelCore] con el mensaje que mando el Core.
  http.Response verificar(
    http.Response respuesta, {
    Set<int> toleradas = const <int>{},
  }) {
    final int estado = respuesta.statusCode;
    if ((estado >= 200 && estado < 300) || toleradas.contains(estado)) {
      return respuesta;
    }
    throw ErrorDelCore(estado, _mensaje(respuesta));
  }

  static String _mensaje(http.Response respuesta) {
    try {
      final Object? cuerpo = jsonDecode(utf8.decode(respuesta.bodyBytes));
      if (cuerpo is Map<String, dynamic> && cuerpo['mensaje'] is String) {
        return cuerpo['mensaje'] as String;
      }
    } on FormatException {
      // Cuerpo vacio o no JSON: se usa el generico de abajo.
    }
    return 'Error ${respuesta.statusCode} del servidor';
  }
}
