import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wearhack/core/atributos_c18.dart';
import 'package:wearhack/core/vocabulario.dart';
import 'package:wearhack/features/closet/captura/cola_captura.dart';
import 'package:wearhack/features/closet/cliente_closet.dart';
import 'package:wearhack/features/closet/prenda.dart';
import 'package:wearhack/features/colorimetria/conexion_core.dart';
import 'package:wearhack/platform/captura/contratos.dart';

void main() {
  const String id = 'c2729148-354d-40ae-925b-c1abce7310e4';
  const String usuario = 'usuario-de-prueba';
  final String token =
      'header.${base64Url.encode(utf8.encode(jsonEncode(<String, String>{'sub': usuario})))}.firma';
  final PrendaClasificada procesada = PrendaClasificada(
    imagenSinFondo: Uint8List.fromList(<int>[137, 80, 78, 71]),
    tipo: TipoC18.camisa,
    confianzaTipo: 0.9,
    patron: PatronC18.liso,
    confianzaPatron: 0.8,
    color: const ColorLab(l: 40, a: -8, b: 19),
    categoriaColor: CategoriaColor.verdeOliva,
  );

  test('la subida usa el UUID y solo envía la imagen procesada', () async {
    final ClienteCloset closet = ClienteCloset(
      ConexionCore(
        cliente: MockClient((http.Request solicitud) async {
          expect(solicitud.method, 'PUT');
          expect(solicitud.url.path, '/api/v1/closet/me/prendas/$id');
          expect(solicitud.headers['authorization'], 'Bearer $token');
          expect(jsonDecode(solicitud.body), <String, Object?>{
            'tipo': 'CAMISA',
            'patron': 'LISO',
            'textura': null,
            'color': <String, Object>{
              'lab': <num>[40, -8, 19],
              'categoria': 'VERDE_OLIVA',
            },
            'imagenPng': base64Encode(procesada.imagenSinFondo),
          });
          return http.Response('{}', 201);
        }),
        base: 'http://127.0.0.1:8090',
        token: () async => token,
      ),
    );
    await closet.subidor(usuario).subir(id, procesada);
    await expectLater(
      closet.subidor('otra-cuenta').subir(id, procesada),
      throwsA(isA<SinConexion>()),
    );
  });

  test('lee del Core una prenda con imagen y atributos opcionales', () async {
    final ClienteCloset closet = ClienteCloset(
      ConexionCore(
        cliente: MockClient((http.Request solicitud) async {
          expect(solicitud.method, 'GET');
          expect(solicitud.url.path, '/api/v1/closet/me/prendas');
          expect(solicitud.headers['authorization'], 'Bearer $token');
          return http.Response('''
            {"prendas":[{
              "id":"$id", "tipo":"GAFAS", "slotOutfit":"ACCESORIO_OJOS",
              "patron":"LISO", "textura":null, "formalidad":null,
              "color":{"lab":[40,-8,19],"categoria":"VERDE_OLIVA"},
              "climaApto":["FRIO","TEMPLADO","CALIDO"],
              "imagenUrl":"http://127.0.0.1:9000/prenda.png?firma=abc"
            }]}
          ''', 200);
        }),
        base: 'http://127.0.0.1:8090',
        token: () async => token,
      ),
    );
    final Prenda prenda = (await closet.prendas()).single;
    expect(prenda.id, id);
    expect(prenda.slot, SlotOutfit.accesorio);
    expect(prenda.tipoCore, 'GAFAS');
    expect(prenda.categoriaColor, CategoriaColor.verdeOliva);
    expect(prenda.texturaCore, isNull);
    expect(prenda.imagenUrl, 'http://127.0.0.1:9000/prenda.png?firma=abc');
  });
}
