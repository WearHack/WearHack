import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wearhack/features/cuenta/cliente_usuarios.dart';
import 'package:wearhack/features/cuenta/plan.dart';

/// Planes Gratis, Esencial y Plus, sin Core de verdad.
void main() {
  test('lee el plan y la cuota del Core', () async {
    late http.Request enviada;
    final ClienteUsuarios cliente = _cliente((http.Request peticion) async {
      enviada = peticion;
      return http.Response(
        jsonEncode(<String, Object?>{
          'plan': 'PLUS',
          'derechos': <String, Object?>{
            'plan': 'PLUS',
            'solicitudesIaPorMes': 30,
            'maxPrendas': null,
            'dressCodesPorMes': null,
            'escaneoEnTienda': true,
            'analisisDelCloset': true,
            'maleta': true,
          },
          'solicitudesIaUsadas': 4,
          'solicitudesIaRestantes': 26,
        }),
        200,
      );
    });

    final EstadoPlan estado = await cliente.plan();

    expect(enviada.url.path, '/api/v1/usuarios/me/plan');
    expect(enviada.headers['Authorization'], 'Bearer token-de-acceso');
    expect(estado.plan, Plan.plus);
    expect(estado.derechos.maxPrendas, isNull);
    expect(estado.derechos.escaneoEnTienda, isTrue);
    expect(estado.solicitudesIaRestantes, 26);
    expect(estado.cuotaAgotada, isFalse);
  });

  test('un plan desconocido o ausente cuenta como gratis', () {
    expect(Plan.desdeCore(null), Plan.gratis);
    expect(Plan.desdeCore('DIAMANTE'), Plan.gratis);
    expect(Plan.desdeCore('ESENCIAL'), Plan.esencial);
  });

  test('el perfil trae el plan, y uno anterior a los planes es gratis', () {
    final PerfilUsuario conPlan = PerfilUsuario.desdeJson(<String, dynamic>{
      'id': 'sub-ana',
      'mayoriaEdadDeclaradaEn': '2026-10-15T12:00:00Z',
      'plan': 'ESENCIAL',
    });
    final PerfilUsuario sinPlan = PerfilUsuario.desdeJson(<String, dynamic>{
      'id': 'sub-ana',
      'mayoriaEdadDeclaradaEn': '2026-10-15T12:00:00Z',
    });

    expect(conPlan.plan, Plan.esencial);
    expect(sinPlan.plan, Plan.gratis);
  });

  test('el 429 del Core es la cuota agotada', () async {
    final ClienteUsuarios cliente = _cliente(
      (_) async => http.Response(
        '{"estado":429,"mensaje":"Ya usaste las 15 solicitudes de IA"}',
        429,
      ),
    );

    expect(
      cliente.plan,
      throwsA(
        isA<ErrorDelCore>()
            .having((ErrorDelCore e) => e.esCuotaAgotada, 'cuota', isTrue)
            .having((ErrorDelCore e) => e.mensaje, 'mensaje', contains('15')),
      ),
    );
  });
}

ClienteUsuarios _cliente(MockClientHandler manejador) => ClienteUsuarios(
  cliente: MockClient(manejador),
  base: 'http://core',
  token: () async => 'token-de-acceso',
);
