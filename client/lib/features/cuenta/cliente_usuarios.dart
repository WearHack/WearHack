/// El perfil de negocio en el Core: `/api/v1/usuarios/me`.
///
/// La cuenta (correo, contrasena) es de Cognito. El Core guarda el perfil
/// ligado al `sub` del token y la declaracion de mayoria de edad.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

class PerfilUsuario {
  const PerfilUsuario({
    required this.id,
    required this.nombre,
    required this.mayoriaEdadDeclaradaEn,
  });

  factory PerfilUsuario.desdeJson(Map<String, dynamic> json) => PerfilUsuario(
    id: json['id'] as String,
    nombre: json['nombre'] as String?,
    mayoriaEdadDeclaradaEn: DateTime.parse(
      json['mayoriaEdadDeclaradaEn'] as String,
    ),
  );

  final String id;
  final String? nombre;
  final DateTime mayoriaEdadDeclaradaEn;
}

/// Una respuesta de error del Core, con su mensaje.
class ErrorDelCore implements Exception {
  ErrorDelCore(this.estado, this.mensaje);

  final int estado;
  final String mensaje;

  @override
  String toString() => mensaje;
}

class ClienteUsuarios {
  ClienteUsuarios({
    required this.cliente,
    required this.base,
    required this.token,
  });

  final http.Client cliente;

  /// Raiz del Core, sin barra final.
  final String base;

  /// El token de acceso de la sesion actual.
  final Future<String> Function() token;

  Uri get _me => Uri.parse('$base/api/v1/usuarios/me');

  /// `null` si la cuenta de Cognito existe pero el registro no se completo.
  Future<PerfilUsuario?> perfil() async {
    final http.Response respuesta = await cliente.get(
      _me,
      headers: await _cabeceras(),
    );
    if (respuesta.statusCode == 404) {
      return null;
    }
    return _perfilDe(respuesta);
  }

  /// Completa el registro. El Core exige [mayorDeEdad] para crear el perfil y
  /// fija la fecha de la declaracion: el reloj del telefono no cuenta.
  Future<PerfilUsuario> completarRegistro({
    String? nombre,
    required bool mayorDeEdad,
  }) async {
    final http.Response respuesta = await cliente.put(
      _me,
      headers: await _cabeceras(),
      body: jsonEncode(<String, Object?>{
        'nombre': nombre,
        'mayorDeEdad': mayorDeEdad,
      }),
    );
    return _perfilDe(respuesta);
  }

  Future<Map<String, String>> _cabeceras() async => <String, String>{
    'Authorization': 'Bearer ${await token()}',
    'Content-Type': 'application/json',
  };

  static PerfilUsuario _perfilDe(http.Response respuesta) {
    if (respuesta.statusCode >= 200 && respuesta.statusCode < 300) {
      return PerfilUsuario.desdeJson(
        jsonDecode(respuesta.body) as Map<String, dynamic>,
      );
    }
    throw ErrorDelCore(respuesta.statusCode, _mensaje(respuesta));
  }

  static String _mensaje(http.Response respuesta) {
    try {
      final Object? cuerpo = jsonDecode(respuesta.body);
      if (cuerpo is Map<String, dynamic> && cuerpo['mensaje'] is String) {
        return cuerpo['mensaje'] as String;
      }
    } on FormatException {
      // Cuerpo vacio o no JSON: se usa el generico de abajo.
    }
    return 'Error ${respuesta.statusCode} del servidor';
  }
}
