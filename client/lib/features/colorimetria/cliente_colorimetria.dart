/// El analisis de colorimetria contra el Core.
///
/// El Core recibe el recorte como cuerpo crudo, lo reenvia al servicio de IA sin
/// guardarlo y persiste solo los valores derivados.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:wearhack/features/colorimetria/conexion_core.dart';
import 'package:wearhack/features/colorimetria/perfil_colorimetria.dart';

class ClienteColorimetria implements ServicioColorimetria {
  ClienteColorimetria(this._conexion);

  final ConexionCore _conexion;

  @override
  Future<PerfilColorimetria> analizar(Uint8List png) async {
    final http.Response respuesta = await _conexion.cliente.post(
      _conexion.uri('/colorimetria'),
      headers: await _conexion.cabeceras(tipo: 'image/png'),
      body: png,
    );
    return _perfilDe(_conexion.verificar(respuesta));
  }

  @override
  Future<PerfilColorimetria?> perfil() async {
    final http.Response respuesta = await _conexion.cliente.get(
      _conexion.uri('/colorimetria'),
      headers: await _conexion.cabeceras(),
    );
    if (respuesta.statusCode == 404) return null;
    return _perfilDe(_conexion.verificar(respuesta));
  }

  @override
  Future<void> borrarPerfil() async {
    final http.Response respuesta = await _conexion.cliente.delete(
      _conexion.uri('/colorimetria'),
      headers: await _conexion.cabeceras(),
    );
    _conexion.verificar(respuesta);
  }

  static PerfilColorimetria _perfilDe(http.Response respuesta) =>
      PerfilColorimetria.desdeJson(
        jsonDecode(utf8.decode(respuesta.bodyBytes)) as Map<String, dynamic>,
      );
}
