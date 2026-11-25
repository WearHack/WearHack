import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wearhack/core/vocabulario.dart';
import 'package:wearhack/features/closet/prenda.dart';
import 'package:wearhack/features/closet/repositorio_closet.dart';
import 'package:wearhack/features/colorimetria/conexion_core.dart';
import 'package:wearhack/features/outfits/cliente_outfits.dart';
import 'package:wearhack/features/outfits/contexto.dart';

void main() {
  const Prenda pantalon = Prenda(
    id: 'pantalon',
    tipo: TipoPrenda.pantalon,
    slot: SlotOutfit.inferior,
    colorLab: ColorLab(l: 40, a: 0, b: 0),
    categoriaColor: CategoriaColor.gris,
    textura: null,
    patron: Patron.solido,
    formalidad: Formalidad.casual,
    climaApto: <Clima>{Clima.templado},
  );
  const Map<String, Object?> outfit = <String, Object?>{
    'id': 'outfit-1',
    'prendas': <String>['pantalon'],
    'formalidad': 'SMART_CASUAL',
    'clima': null,
  };

  test('genera con el contexto y usa las prendas reales del clóset', () async {
    final ClienteOutfits cliente = ClienteOutfits(
      _conexion((http.Request peticion) {
        expect(peticion.method, 'POST');
        expect(peticion.url.path, '/api/v1/outfits/me/hoy');
        expect(jsonDecode(peticion.body), <String, Object?>{
          'ocasion': 'SALIDA_CASUAL',
          'mood': 'ELEGANTE',
          'clima': null,
        });
        return http.Response(
          jsonEncode(<String, Object?>{
            'id': 'lote-1',
            'fecha': '2026-11-24',
            'opciones': <Object>[outfit],
          }),
          200,
        );
      }),
      const _Closet(<Prenda>[pantalon]),
    );

    final lote = await cliente.opcionesDeHoy(
      const ContextoOutfit(ocasion: Ocasion.salidaCasual, mood: Mood.elegante),
    );
    expect(lote.opciones.single.prendas[SlotOutfit.inferior], pantalon);
    expect(lote.opciones.single.formalidad, Formalidad.smartCasual);
    expect(lote.opciones.single.clima, isNull);
  });

  test('una prenda eliminada invalida la tarjeta de un día asignado', () async {
    final ClienteOutfits cliente = ClienteOutfits(
      _conexion((http.Request peticion) {
        expect(peticion.method, 'GET');
        expect(peticion.url.path, '/api/v1/outfits/me/semana');
        return http.Response(
          jsonEncode(<String, Object>{
            'dias': <Map<String, Object>>[
              <String, Object>{'fecha': '2026-11-24', 'outfit': outfit},
            ],
          }),
          200,
        );
      }),
      const _Closet(<Prenda>[]),
    );

    final plan = await cliente.planSemanal();
    expect(plan.single.fecha, DateTime(2026, 11, 24));
    expect(plan.single.outfit, isNull);
  });

  test(
    'permite dejar un día libre y registra la elección con el lote',
    () async {
      final List<http.Request> peticiones = <http.Request>[];
      final ClienteOutfits cliente = ClienteOutfits(
        _conexion((http.Request peticion) {
          peticiones.add(peticion);
          return http.Response('', 204);
        }),
        const _Closet(<Prenda>[]),
      );
      await cliente.asignarOutfit(DateTime(2026, 11, 24), null);
      await cliente.elegir('lote-1', 'outfit-1');

      expect(peticiones.first.method, 'PUT');
      expect(peticiones.first.url.path, '/api/v1/outfits/me/semana/2026-11-24');
      expect(jsonDecode(peticiones.first.body), <String, Object?>{
        'outfitId': null,
      });
      expect(peticiones.last.url.path, '/api/v1/outfits/me/hoy/eleccion');
      expect(jsonDecode(peticiones.last.body), <String, String>{
        'loteId': 'lote-1',
        'outfitId': 'outfit-1',
      });
    },
  );
}

ConexionCore _conexion(http.Response Function(http.Request) atender) =>
    ConexionCore(
      cliente: MockClient((http.Request peticion) async {
        expect(peticion.headers['authorization'], 'Bearer sesion');
        return atender(peticion);
      }),
      base: 'http://127.0.0.1:8090',
      token: () async => 'sesion',
    );

class _Closet implements RepositorioCloset {
  const _Closet(this._prendas);

  final List<Prenda> _prendas;

  @override
  Future<List<Prenda>> prendas() async => _prendas;
}
