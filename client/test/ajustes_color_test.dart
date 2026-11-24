/// Los ajustes de categoria que decide el Core (#58): como se leen y como
/// cambian la tabla.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wearhack/core/color/categoria_color.dart';
import 'package:wearhack/core/vocabulario.dart';
import 'package:wearhack/features/closet/colores/cliente_ajustes_color.dart';
import 'package:wearhack/features/cuenta/cliente_usuarios.dart';

void main() {
  final TablaIsccNbs tabla = TablaIsccNbs.desdeJson(
    File(assetTablaIsccNbs).readAsStringSync(),
  );
  // Centroide de "strong red" (bloque 12), que la tabla traduce a rojo.
  const ColorLab rojoFuerte = ColorLab(l: 45.75, a: 53.81, b: 22.02);

  group('conAjustes', () {
    test('cambia la categoria del bloque y deja el resto', () {
      final TablaIsccNbs ajustada = tabla.conAjustes(<int, CategoriaColor>{
        12: CategoriaColor.vinotinto,
      });

      expect(tabla.categoria(rojoFuerte), CategoriaColor.rojo);
      expect(ajustada.categoria(rojoFuerte), CategoriaColor.vinotinto);
      expect(ajustada.bloques[10].categoria, tabla.bloques[10].categoria);
      expect(ajustada.bloques[11].lab.l, tabla.bloques[11].lab.l);
    });

    test('sin ajustes devuelve la misma tabla', () {
      expect(
        identical(tabla.conAjustes(const <int, CategoriaColor>{}), tabla),
        isTrue,
      );
    });
  });

  group('ClienteAjustesColor', () {
    ClienteAjustesColor cliente(MockClient http) => ClienteAjustesColor(
      cliente: http,
      base: 'https://core.test',
      token: () async => 'token-de-prueba',
    );

    test('lee los ajustes con el token de la sesion', () async {
      late http.Request recibida;
      final Map<int, CategoriaColor> ajustes = await cliente(
        MockClient((http.Request r) async {
          recibida = r;
          return http.Response(
            jsonEncode(<String, Object?>{
              'ajustes': <Object?>[
                <String, Object?>{
                  'bloque': 12,
                  'categoria': 'VINOTINTO',
                  'desde': '2026-11-19T09:00:00Z',
                },
                <String, Object?>{
                  'bloque': 106,
                  'categoria': 'VERDE_OLIVA',
                  'desde': '2026-11-19T09:00:00Z',
                },
              ],
            }),
            200,
          );
        }),
      ).ajustes();

      expect(recibida.url.path, '/api/v1/closet/colores/ajustes');
      expect(recibida.headers['Authorization'], 'Bearer token-de-prueba');
      expect(ajustes, <int, CategoriaColor>{
        12: CategoriaColor.vinotinto,
        106: CategoriaColor.verdeOliva,
      });
    });

    test('salta una categoria que esta version no conoce', () async {
      final Map<int, CategoriaColor> ajustes = await cliente(
        MockClient(
          (_) async => http.Response(
            '{"ajustes":[{"bloque":12,"categoria":"CORAL","desde":null},'
            '{"bloque":13,"categoria":"ROJO","desde":null}]}',
            200,
          ),
        ),
      ).ajustes();

      expect(ajustes, <int, CategoriaColor>{13: CategoriaColor.rojo});
    });

    test('un error del Core se lanza', () async {
      await expectLater(
        cliente(MockClient((_) async => http.Response('', 503))).ajustes(),
        throwsA(isA<ErrorDelCore>()),
      );
    });
  });
}
