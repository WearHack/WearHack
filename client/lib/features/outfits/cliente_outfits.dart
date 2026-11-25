import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:wearhack/core/vocabulario.dart';
import 'package:wearhack/features/closet/prenda.dart';
import 'package:wearhack/features/closet/repositorio_closet.dart';
import 'package:wearhack/features/colorimetria/conexion_core.dart';
import 'package:wearhack/features/outfits/contexto.dart';
import 'package:wearhack/features/outfits/outfit.dart';
import 'package:wearhack/features/outfits/repositorio_outfits.dart';

typedef _Json = Map<String, Object?>;

class ClienteOutfits implements RepositorioOutfits {
  const ClienteOutfits(this._conexion, this._closet);

  final ConexionCore _conexion;
  final RepositorioCloset _closet;

  @override
  Future<List<Outfit>> outfitsDeLaSemana() async {
    final _Json datos = await _consultar(
      '/semana/outfits',
      cuerpo: <String, Object?>{},
    );
    final List<Object?> opciones = datos['outfits']! as List<Object?>;
    if (opciones.isEmpty) return <Outfit>[];
    return _opciones(opciones, await _prendas());
  }

  @override
  Future<List<DiaPlan>> planSemanal() async {
    final _Json datos = await _consultar('/semana');
    final List<_Json> dias = (datos['dias']! as List<Object?>).cast<_Json>();
    final Map<String, Prenda> prendas = dias.any((dia) => dia['outfit'] != null)
        ? await _prendas()
        : <String, Prenda>{};
    return <DiaPlan>[
      for (final _Json dia in dias)
        DiaPlan(
          fecha: DateTime.parse(dia['fecha']! as String),
          outfit: _outfit(dia['outfit'] as _Json?, prendas),
        ),
    ];
  }

  @override
  Future<void> asignarOutfit(DateTime dia, String? outfitId) async {
    final String fecha = dia.toIso8601String().split('T').first;
    await _consultar(
      '/semana/$fecha',
      metodo: 'PUT',
      cuerpo: <String, Object?>{'outfitId': outfitId},
    );
  }

  @override
  Future<LoteOpciones> opcionesDeHoy(ContextoOutfit contexto) async {
    final _Json datos = await _consultar(
      '/hoy',
      cuerpo: <String, Object?>{
        'ocasion': _codigo(contexto.ocasion),
        'mood': contexto.mood?.name.toUpperCase(),
        'clima': contexto.clima?.name.toUpperCase(),
      },
    );
    final List<Object?> opciones = datos['opciones']! as List<Object?>;
    final Map<String, Prenda> prendas =
        opciones.isEmpty && datos['elegido'] == null
        ? <String, Prenda>{}
        : await _prendas();
    return LoteOpciones(
      id: datos['id']! as String,
      fecha: DateTime.parse(datos['fecha']! as String),
      contexto: contexto,
      opciones: _opciones(opciones, prendas),
      elegidoId: datos['elegidoId'] as String?,
      elegido: _outfit(datos['elegido'] as _Json?, prendas),
    );
  }

  @override
  Future<void> elegir(String loteId, String outfitId) async {
    await _consultar(
      '/hoy/eleccion',
      cuerpo: <String, Object?>{'loteId': loteId, 'outfitId': outfitId},
    );
  }

  Future<_Json> _consultar(String ruta, {String? metodo, _Json? cuerpo}) async {
    final Uri uri = Uri.parse('${_conexion.base}/api/v1/outfits/me$ruta');
    final http.Request peticion = http.Request(
      metodo ?? (cuerpo == null ? 'GET' : 'POST'),
      uri,
    );
    peticion.headers.addAll(
      await _conexion.cabeceras(
        tipo: cuerpo == null ? null : 'application/json',
      ),
    );
    if (cuerpo != null) peticion.body = jsonEncode(cuerpo);
    final http.Response respuesta = _conexion.verificar(
      await _conexion.cliente
          .send(peticion)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 20)),
    );
    return respuesta.statusCode == 204
        ? <String, Object?>{}
        : jsonDecode(utf8.decode(respuesta.bodyBytes)) as _Json;
  }

  Future<Map<String, Prenda>> _prendas() async => <String, Prenda>{
    for (final Prenda prenda in await _closet.prendas()) prenda.id: prenda,
  };

  static List<Outfit> _opciones(
    List<Object?> opciones,
    Map<String, Prenda> prendas,
  ) => <Outfit>[
    for (final Object? opcion in opciones)
      if (_outfit(opcion as _Json, prendas) case final Outfit outfit) outfit,
  ];

  static Outfit? _outfit(_Json? datos, Map<String, Prenda> prendas) {
    if (datos == null) return null;
    final Map<SlotOutfit, Prenda> combinacion = <SlotOutfit, Prenda>{};
    for (final String id
        in (datos['prendas']! as List<Object?>).cast<String>()) {
      final Prenda? prenda = prendas[id];
      if (prenda == null) return null;
      combinacion[prenda.slot] = prenda;
    }
    final String? clima = datos['clima'] as String?;
    final String formalidad = datos['formalidad']! as String;
    return Outfit(
      id: datos['id']! as String,
      prendas: combinacion,
      formalidad: formalidad == 'SMART_CASUAL'
          ? Formalidad.smartCasual
          : Formalidad.values.byName(formalidad.toLowerCase()),
      clima: clima == null ? null : Clima.values.byName(clima.toLowerCase()),
    );
  }

  static String _codigo(Ocasion ocasion) => switch (ocasion) {
    Ocasion.diaADia => 'DIA_A_DIA',
    _ =>
      ocasion.name
          .replaceAllMapped(RegExp('[A-Z]'), (Match m) => '_${m[0]}')
          .toUpperCase(),
  };
}
