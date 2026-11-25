import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:wearhack/core/vocabulario.dart';
import 'package:wearhack/features/closet/captura/cola_captura.dart';
import 'package:wearhack/features/closet/prenda.dart';
import 'package:wearhack/features/closet/repositorio_closet.dart';
import 'package:wearhack/features/colorimetria/conexion_core.dart';
import 'package:wearhack/features/cuenta/cliente_usuarios.dart';
import 'package:wearhack/platform/captura/contratos.dart';

class ClienteCloset implements ClosetConBorrado {
  ClienteCloset(this.conexion);

  final ConexionCore conexion;
  static const Duration _espera = Duration(seconds: 30);

  Uri _uri([String? id]) => Uri.parse(
    '${conexion.base}/api/v1/closet/me/prendas${id == null ? '' : '/${Uri.encodeComponent(id)}'}',
  );

  @override
  Future<List<Prenda>> prendas() async {
    final http.Response respuesta = conexion.verificar(
      await conexion.cliente
          .get(_uri(), headers: await conexion.cabeceras())
          .timeout(_espera),
    );
    final Map<String, Object?> cuerpo =
        jsonDecode(utf8.decode(respuesta.bodyBytes)) as Map<String, Object?>;
    return <Prenda>[
      for (final Object? prenda in cuerpo['prendas']! as List<Object?>)
        _prenda(prenda! as Map<String, Object?>),
    ];
  }

  @override
  Future<void> eliminarPrenda(String id) async {
    conexion.verificar(
      await conexion.cliente
          .delete(_uri(id), headers: await conexion.cabeceras())
          .timeout(_espera),
    );
  }

  SubidorDePrendas subidor(String usuario) => _SubidorCore(this, usuario);

  static String sujeto(String token) {
    final String carga = token.split('.')[1];
    final Map<String, Object?> datos = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(carga))),
    ) as Map<String, Object?>;
    return datos['sub']! as String;
  }

  static Prenda _prenda(Map<String, Object?> datos) {
    final String codigoTipo = datos['tipo']! as String;
    final String codigoPatron = datos['patron']! as String;
    final Map<String, Object?> color = datos['color']! as Map<String, Object?>;
    final List<Object?> lab = color['lab']! as List<Object?>;
    return Prenda(
      id: datos['id']! as String,
      tipo: switch (codigoTipo) {
        'CARDIGAN' => TipoPrenda.sueter,
        'CHALECO' => TipoPrenda.chaqueta,
        'ENTERIZO' => TipoPrenda.vestido,
        'CALZADO' => switch (datos['subtipoCalzado']) {
          'TENIS' => TipoPrenda.tenis,
          'BOTAS' => TipoPrenda.bota,
          'SANDALIAS' => TipoPrenda.sandalia,
          _ => TipoPrenda.zapato,
        },
        _ =>
          TipoPrenda.values.asNameMap()[codigoTipo.toLowerCase()] ??
              TipoPrenda.accesorio,
      },
      slot: switch (datos['slotOutfit']) {
        'TORSO_SUPERIOR' => SlotOutfit.superior,
        'TORSO_INFERIOR' => SlotOutfit.inferior,
        'CUERPO_COMPLETO' => SlotOutfit.cuerpoEntero,
        'CALZADO' => SlotOutfit.calzado,
        'EXTERIOR' => SlotOutfit.exterior,
        _ => SlotOutfit.accesorio,
      },
      colorLab: ColorLab(
        l: (lab[0]! as num).toDouble(),
        a: (lab[1]! as num).toDouble(),
        b: (lab[2]! as num).toDouble(),
      ),
      categoriaColor: CategoriaColor.desdeCodigo(color['categoria']! as String),
      textura: null,
      patron: switch (codigoPatron) {
        'LISO' => Patron.solido,
        'PUNTOS' => Patron.lunares,
        'OTRO_ESTAMPADO' => Patron.estampado,
        _ => Patron.values.byName(codigoPatron.toLowerCase()),
      },
      formalidad: null,
      climaApto: <Clima>{
        for (final Object? clima in datos['climaApto']! as List<Object?>)
          Clima.values.byName((clima! as String).toLowerCase()),
      },
      imagenUrl: datos['imagenUrl'] as String?,
      tipoCore: codigoTipo,
      texturaCore: datos['textura'] as String?,
      formalidadCore: _rango(datos['formalidad'] as Map<String, Object?>?),
    );
  }

  static String? _rango(Map<String, Object?>? rango) {
    if (rango == null) return null;
    final String minimo = rango['min']! as String;
    final String maximo = rango['max']! as String;
    return minimo == maximo ? minimo : '$minimo – $maximo';
  }
}

class _SubidorCore implements SubidorDePrendas {
  const _SubidorCore(this.closet, this.usuario);

  final ClienteCloset closet;
  final String usuario;

  @override
  Future<void> subir(String id, PrendaClasificada prenda) async {
    final String token;
    try {
      token = await closet.conexion.token().timeout(ClienteCloset._espera);
    } on Exception {
      throw const SinConexion('No se pudo obtener la sesión de Cognito');
    }
    if (ClienteCloset.sujeto(token) != usuario) {
      throw const SinConexion('La sesión cambió');
    }
    try {
      closet.conexion.verificar(
        await closet.conexion.cliente
            .put(
              closet._uri(id),
              headers: <String, String>{
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode(<String, Object?>{
                'tipo': prenda.tipo.codigo,
                'patron': prenda.patron.codigo,
                'textura': prenda.textura?.codigo,
                'color': <String, Object>{
                  'lab': <double>[
                    prenda.color.l,
                    prenda.color.a,
                    prenda.color.b,
                  ],
                  'categoria': prenda.categoriaColor.codigo,
                },
                'imagenPng': base64Encode(prenda.imagenSinFondo),
              }),
            )
            .timeout(ClienteCloset._espera),
      );
    } on http.ClientException {
      throw const SinConexion('No se pudo conectar al Core');
    } on TimeoutException {
      throw const SinConexion('El Core tardó demasiado en responder');
    } on ErrorDelCore catch (error) {
      if (error.estado == 401 || error.estado >= 500) {
        throw SinConexion(error.toString());
      }
      rethrow;
    }
  }
}
