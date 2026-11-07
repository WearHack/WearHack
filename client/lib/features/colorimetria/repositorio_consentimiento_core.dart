/// El consentimiento de colorimetria guardado en el Core.
///
/// El Core es la fuente de verdad: guarda la version del texto que vio la
/// persona, cuando, y el estado (otorgado, revocado o sustituido).
///
/// **Omitir no se envia.** Quien omite no autoriza nada, asi que no hay
/// evidencia que guardar. La decision solo se recuerda mientras la app siga
/// abierta, para no insistir.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:wearhack/features/colorimetria/conexion_core.dart';
import 'package:wearhack/features/colorimetria/consentimiento.dart';
import 'package:wearhack/features/colorimetria/repositorio_consentimiento.dart';

class RepositorioConsentimientoCore implements RepositorioConsentimiento {
  RepositorioConsentimientoCore(this._conexion, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  static const String _finalidad = 'colorimetria';

  final ConexionCore _conexion;
  final DateTime Function() _ahora;

  DateTime? _omitidoEn;

  @override
  Future<Consentimiento?> consentimientoColorimetria() async {
    final http.Response respuesta = await _conexion.cliente.get(
      _conexion.uri('/consentimientos'),
      headers: await _conexion.cabeceras(),
    );
    _conexion.verificar(respuesta);
    final Object? historial = jsonDecode(utf8.decode(respuesta.bodyBytes));

    // Viene del mas reciente al mas antiguo. Lo que cuenta es el vigente.
    for (final Object? e in historial as List<Object?>) {
      final Map<String, dynamic> c = e! as Map<String, dynamic>;
      if (c['finalidad'] == _finalidad && c['estado'] == 'otorgado') {
        return Consentimiento(
          decision: DecisionConsentimiento.autorizo,
          // Un texto que no sea de este cliente (no es un entero) cuenta como
          // version desconocida: hay que volver a pedirlo.
          version: int.tryParse(c['versionTexto'] as String) ?? -1,
          fecha: DateTime.parse(c['otorgadoEn'] as String),
        );
      }
    }

    final DateTime? omitido = _omitidoEn;
    if (omitido != null) {
      return Consentimiento(
        decision: DecisionConsentimiento.omitio,
        version: versionTextoConsentimiento,
        fecha: omitido,
      );
    }
    return null;
  }

  @override
  Future<void> registrar(DecisionConsentimiento decision, int version) async {
    if (decision == DecisionConsentimiento.omitio) {
      _omitidoEn = _ahora();
      return;
    }
    final http.Response respuesta = await _conexion.cliente.post(
      _conexion.uri('/consentimientos'),
      headers: await _conexion.cabeceras(tipo: 'application/json'),
      body: jsonEncode(<String, String>{
        'finalidad': _finalidad,
        'versionTexto': '$version',
      }),
    );
    _conexion.verificar(respuesta);
    _omitidoEn = null;
  }

  @override
  Future<void> revocar() async {
    final http.Response respuesta = await _conexion.cliente.delete(
      _conexion.uri('/consentimientos/$_finalidad'),
      headers: await _conexion.cabeceras(),
    );
    // 404: ya no habia uno vigente. El resultado que se queria es el mismo.
    _conexion.verificar(respuesta, toleradas: const <int>{404});
    _omitidoEn = null;
  }
}
