/// La colorimetria contra el Core (issue #14): lo que el cliente manda y como
/// lee las respuestas, sin red y sin el Core (con un cliente HTTP falso).
///
/// El contrato esta en `docs/api-usuarios.md`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wearhack/features/colorimetria/cliente_colorimetria.dart';
import 'package:wearhack/features/colorimetria/conexion_core.dart';
import 'package:wearhack/features/colorimetria/consentimiento.dart';
import 'package:wearhack/features/colorimetria/perfil_colorimetria.dart';
import 'package:wearhack/features/colorimetria/repositorio_consentimiento_core.dart';
import 'package:wearhack/features/cuenta/cliente_usuarios.dart';

/// Una respuesta JSON en UTF-8, como la manda el Core.
http.Response _json(String cuerpo, [int estado = 200]) => http.Response(
  cuerpo,
  estado,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

/// Un Core falso: guarda lo que le llega y responde lo que diga [responder].
class _CoreFalso {
  _CoreFalso(this.responder);

  final http.Response Function(http.Request) responder;
  final List<http.Request> peticiones = <http.Request>[];

  ConexionCore get conexion => ConexionCore(
    cliente: MockClient((http.Request p) async {
      peticiones.add(p);
      return responder(p);
    }),
    base: 'http://core',
    token: () async => 'tok',
  );
}

const String _perfilJson =
    '{"temporada":"primavera_clara","confianza":0.82,'
    '"piel":{"l":70,"a":15,"b":20},"cabello":{"l":30,"a":5,"b":10},'
    '"iris":null,"ejes":["calido","claro"],'
    '"calculadoEn":"2026-11-07T15:00:00Z"}';

void main() {
  group('ClienteColorimetria', () {
    test(
      'analizar manda el recorte crudo, con el token, y lee el perfil',
      () async {
        final _CoreFalso core = _CoreFalso((_) => _json(_perfilJson));
        final Uint8List png = Uint8List.fromList(<int>[137, 80, 78, 71, 1, 2]);

        final PerfilColorimetria perfil = await ClienteColorimetria(
          core.conexion,
        ).analizar(png);

        final http.Request p = core.peticiones.single;
        expect(p.method, 'POST');
        expect(p.url.toString(), 'http://core/api/v1/usuarios/me/colorimetria');
        expect(p.headers['Authorization'], 'Bearer tok');
        expect(p.headers['Content-Type'], startsWith('image/png'));
        expect(p.bodyBytes, png);

        expect(perfil.temporada, 'primavera_clara');
        expect(perfil.confianza, 0.82);
        expect(perfil.piel!.l, 70);
        expect(perfil.cabello!.b, 10);
        expect(perfil.iris, isNull);
        expect(perfil.ejes, <String>['calido', 'claro']);
        expect(perfil.calculadoEn, DateTime.utc(2026, 11, 7, 15));
      },
    );

    test('un perfil sin clasificar sigue leyendose', () async {
      final _CoreFalso core = _CoreFalso(
        (_) => _json(
          '{"temporada":null,"confianza":null,"piel":null,"cabello":null,'
          '"iris":null,"ejes":[],"calculadoEn":null}',
        ),
      );
      final PerfilColorimetria perfil = await ClienteColorimetria(core.conexion)
          .analizar(Uint8List(1));
      expect(perfil.temporada, isNull);
      expect(perfil.ejes, isEmpty);
    });

    test('un 422 llega con el mensaje del Core, tildes incluidas', () async {
      final _CoreFalso core = _CoreFalso(
        (_) => _json(
          '{"estado":422,"mensaje":"No se ve el rostro: repite la foto"}',
          422,
        ),
      );
      await expectLater(
        ClienteColorimetria(core.conexion).analizar(Uint8List(1)),
        throwsA(
          isA<ErrorDelCore>()
              .having((ErrorDelCore e) => e.estado, 'estado', 422)
              .having(
                (ErrorDelCore e) => e.mensaje,
                'mensaje',
                'No se ve el rostro: repite la foto',
              ),
        ),
      );
    });

    test('un error sin cuerpo JSON usa el mensaje generico', () async {
      final _CoreFalso core = _CoreFalso((_) => http.Response('', 503));
      await expectLater(
        ClienteColorimetria(core.conexion).analizar(Uint8List(1)),
        throwsA(
          isA<ErrorDelCore>()
              .having((ErrorDelCore e) => e.estado, 'estado', 503)
              .having(
                (ErrorDelCore e) => e.mensaje,
                'mensaje',
                'Error 503 del servidor',
              ),
        ),
      );
    });

    test('perfil: 404 es "no hay", 200 es el perfil', () async {
      int estado = 404;
      final _CoreFalso core = _CoreFalso(
        (_) => estado == 404 ? http.Response('', 404) : _json(_perfilJson),
      );
      final ClienteColorimetria cliente = ClienteColorimetria(core.conexion);

      expect(await cliente.perfil(), isNull);
      estado = 200;
      expect((await cliente.perfil())!.temporada, 'primavera_clara');
      expect(core.peticiones.first.method, 'GET');
    });

    test('borrarPerfil usa DELETE; un fallo no se traga', () async {
      int estado = 204;
      final _CoreFalso core = _CoreFalso((_) => http.Response('', estado));
      final ClienteColorimetria cliente = ClienteColorimetria(core.conexion);

      await cliente.borrarPerfil();
      expect(core.peticiones.single.method, 'DELETE');
      expect(
        core.peticiones.single.url.path,
        '/api/v1/usuarios/me/colorimetria',
      );

      estado = 500;
      await expectLater(cliente.borrarPerfil(), throwsA(isA<ErrorDelCore>()));
    });
  });

  group('RepositorioConsentimientoCore', () {
    String vigente(String version) =>
        '{"id":"c1","finalidad":"colorimetria","versionTexto":"$version",'
        '"estado":"otorgado","otorgadoEn":"2026-10-22T12:00:00Z",'
        '"revocadoEn":null}';
    String viejo(String estado) =>
        '{"id":"c0","finalidad":"colorimetria","versionTexto":"1",'
        '"estado":"$estado","otorgadoEn":"2026-10-01T12:00:00Z",'
        '"revocadoEn":"2026-10-10T12:00:00Z"}';

    Future<Consentimiento?> leer(String historial) {
      final _CoreFalso core = _CoreFalso((_) => _json(historial));
      return RepositorioConsentimientoCore(core.conexion)
          .consentimientoColorimetria();
    }

    test(
      'el consentimiento otorgado con el texto vigente permite capturar',
      () async {
        final Consentimiento? c = await leer(
          '[${vigente('$versionTextoConsentimiento')},${viejo('revocado')}]',
        );
        expect(c!.decision, DecisionConsentimiento.autorizo);
        expect(c.version, versionTextoConsentimiento);
        expect(c.fecha, DateTime.utc(2026, 10, 22, 12));
        expect(c.vigente, isTrue);
      },
    );

    test('otorgado sobre otro texto cuenta como desactualizado', () async {
      for (final String version in <String>['0', '2026-10-01']) {
        final Consentimiento? c = await leer('[${vigente(version)}]');
        expect(c!.vigente, isFalse, reason: 'version $version');
        expect(c.desactualizado, isTrue, reason: 'version $version');
      }
    });

    test('revocado o sustituido no es un consentimiento', () async {
      expect(
        await leer('[${viejo('revocado')},${viejo('sustituido')}]'),
        isNull,
      );
      expect(await leer('[]'), isNull);
    });

    test('autorizar manda la finalidad y la version del texto', () async {
      final _CoreFalso core = _CoreFalso((_) => _json(vigente('1'), 201));
      await RepositorioConsentimientoCore(core.conexion)
          .registrar(DecisionConsentimiento.autorizo, 1);

      final http.Request p = core.peticiones.single;
      expect(p.method, 'POST');
      expect(p.url.path, '/api/v1/usuarios/me/consentimientos');
      expect(p.headers['Authorization'], 'Bearer tok');
      expect(jsonDecode(p.body), <String, String>{
        'finalidad': 'colorimetria',
        'versionTexto': '1',
      });
    });

    test(
      'omitir no manda nada al Core y se recuerda mientras la app vive',
      () async {
        final _CoreFalso core = _CoreFalso((_) => _json('[]'));
        final RepositorioConsentimientoCore repo =
            RepositorioConsentimientoCore(
              core.conexion,
              ahora: () => DateTime(2026, 11, 7),
            );

        await repo.registrar(DecisionConsentimiento.omitio, 1);
        expect(core.peticiones, isEmpty);

        final Consentimiento? c = await repo.consentimientoColorimetria();
        expect(c!.decision, DecisionConsentimiento.omitio);
        expect(c.vigente, isFalse);
        expect(c.fecha, DateTime(2026, 11, 7));
      },
    );

    test('revocar usa DELETE y tolera que ya no hubiera uno', () async {
      int estado = 204;
      final _CoreFalso core = _CoreFalso((_) => http.Response('', estado));
      final RepositorioConsentimientoCore repo = RepositorioConsentimientoCore(
        core.conexion,
      );

      await repo.revocar();
      expect(core.peticiones.single.method, 'DELETE');
      expect(
        core.peticiones.single.url.path,
        '/api/v1/usuarios/me/consentimientos/colorimetria',
      );

      estado = 404;
      await repo.revocar();

      estado = 500;
      await expectLater(repo.revocar(), throwsA(isA<ErrorDelCore>()));
    });
  });
}
