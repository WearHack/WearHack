import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wearhack/features/cuenta/autenticacion.dart';
import 'package:wearhack/features/cuenta/cliente_usuarios.dart';
import 'package:wearhack/features/cuenta/configuracion_cognito.dart';
import 'package:wearhack/features/cuenta/ui/pantalla_completar_registro.dart';
import 'package:wearhack/features/cuenta/ui/puerta_de_acceso.dart';

/// Registro e inicio de sesion (issue #10), sin Cognito ni Core de verdad.
void main() {
  group('configuracion de Amplify', () {
    test('sin dominio no hay Hosted UI ni Google', () {
      final Map<String, dynamic> salidas = _auth(
        salidasAmplify(
          region: 'us-east-1',
          userPoolId: 'us-east-1_Abc',
          clientId: 'cliente',
        ),
      );

      expect(salidas['user_pool_id'], 'us-east-1_Abc');
      expect(salidas['user_pool_client_id'], 'cliente');
      expect(salidas.containsKey('oauth'), isFalse);
    });

    test('con dominio, Google vuelve a la app por wearhack://', () {
      final Map<String, dynamic> oauth =
          _auth(
                salidasAmplify(
                  region: 'us-east-1',
                  userPoolId: 'us-east-1_Abc',
                  clientId: 'cliente',
                  dominio: 'wearhack-x.auth.us-east-1.amazoncognito.com',
                ),
              )['oauth']
              as Map<String, dynamic>;

      expect(oauth['identity_providers'], <String>['GOOGLE']);
      expect(oauth['redirect_sign_in_uri'], <String>[redireccionInicio]);
      expect(oauth['response_type'], 'code');
    });
  });

  group('cliente del Core', () {
    test('manda el token de acceso y la declaracion', () async {
      late http.Request enviada;
      final ClienteUsuarios cliente = _cliente((http.Request peticion) async {
        enviada = peticion;
        return _perfil(201);
      });

      final PerfilUsuario perfil = await cliente.completarRegistro(
        nombre: 'Ana',
        mayorDeEdad: true,
      );

      expect(enviada.method, 'PUT');
      expect(enviada.url.path, '/api/v1/usuarios/me');
      expect(enviada.headers['Authorization'], 'Bearer token-de-acceso');
      expect(jsonDecode(enviada.body), <String, Object>{
        'nombre': 'Ana',
        'mayorDeEdad': true,
      });
      expect(perfil.id, 'sub-ana');
    });

    test('sin perfil en el Core devuelve null', () async {
      final ClienteUsuarios cliente = _cliente(
        (_) async => http.Response('{"estado":404}', 404),
      );

      expect(await cliente.perfil(), isNull);
    });

    test('un error del Core trae su mensaje', () async {
      final ClienteUsuarios cliente = _cliente(
        (_) async => http.Response(
          '{"estado":422,"mensaje":"WearHack es solo para mayores de 18"}',
          422,
        ),
      );

      expect(
        () => cliente.completarRegistro(mayorDeEdad: false),
        throwsA(
          isA<ErrorDelCore>().having(
            (ErrorDelCore e) => e.mensaje,
            'mensaje',
            contains('mayores de 18'),
          ),
        ),
      );
    });
  });

  group('declaracion de mayoria de edad', () {
    testWidgets('no se puede continuar sin marcar la casilla', (
      WidgetTester tester,
    ) async {
      String? enviado;
      bool completado = false;
      await tester.pumpWidget(
        MaterialApp(
          home: PantallaCompletarRegistro(
            hoy: DateTime(2026, 10, 15),
            alCompletar: (String? nombre) async {
              enviado = nombre;
              completado = true;
            },
            alCancelar: () {},
          ),
        ),
      );

      expect(find.text('Fecha de la declaracion: 2026-10-15'), findsOneWidget);
      await tester.tap(find.text('Continuar'));
      await tester.pump();
      expect(completado, isFalse);

      await tester.enterText(find.byType(TextField), ' Ana ');
      await tester.tap(find.byKey(const Key('casilla-mayoria-edad')));
      await tester.pump();
      await tester.tap(find.text('Continuar'));
      await tester.pump();

      expect(completado, isTrue);
      expect(enviado, 'Ana');
    });
  });

  group('puerta de acceso', () {
    testWidgets('sin sesion muestra el acceso', (WidgetTester tester) async {
      await tester.pumpWidget(
        _puerta(_AutenticacionFalsa(sesion: false), (_) async => _perfil(200)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Entrar'), findsOneWidget);
      expect(find.text('Continuar con Google'), findsOneWidget);
    });

    testWidgets('con sesion y sin perfil pide la declaracion y luego entra', (
      WidgetTester tester,
    ) async {
      bool registrado = false;
      await tester.pumpWidget(
        _puerta(_AutenticacionFalsa(sesion: true), (
          http.Request peticion,
        ) async {
          if (peticion.method == 'PUT') {
            registrado = true;
            return _perfil(201);
          }
          return http.Response('', 404);
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('Completa tu registro'), findsOneWidget);

      await tester.tap(find.byKey(const Key('casilla-mayoria-edad')));
      await tester.pump();
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();

      expect(registrado, isTrue);
      expect(find.text('la app'), findsOneWidget);
    });

    testWidgets('con sesion y perfil entra directo', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _puerta(_AutenticacionFalsa(sesion: true), (_) async => _perfil(200)),
      );
      await tester.pumpAndSettle();

      expect(find.text('la app'), findsOneWidget);
    });
  });
}

Map<String, dynamic> _auth(String salidas) =>
    (jsonDecode(salidas) as Map<String, dynamic>)['auth']
        as Map<String, dynamic>;

http.Response _perfil(int estado) => http.Response(
  jsonEncode(<String, Object?>{
    'id': 'sub-ana',
    'nombre': 'Ana',
    'mayorDeEdad': true,
    'mayoriaEdadDeclaradaEn': '2026-10-15T12:00:00Z',
  }),
  estado,
);

ClienteUsuarios _cliente(MockClientHandler manejador) => ClienteUsuarios(
  cliente: MockClient(manejador),
  base: 'http://core',
  token: () async => 'token-de-acceso',
);

Widget _puerta(Autenticacion autenticacion, MockClientHandler manejador) =>
    MaterialApp(
      home: PuertaDeAcceso(
        autenticacion: autenticacion,
        usuarios: _cliente(manejador),
        app: const Text('la app'),
      ),
    );

class _AutenticacionFalsa implements Autenticacion {
  _AutenticacionFalsa({required this.sesion});

  bool sesion;

  @override
  bool get googleDisponible => true;

  @override
  Future<bool> haySesion() async => sesion;

  @override
  Future<void> registrarse(String correo, String clave) async {}

  @override
  Future<void> confirmarRegistro(String correo, String codigo) async {}

  @override
  Future<void> iniciarSesion(String correo, String clave) async =>
      sesion = true;

  @override
  Future<void> iniciarConGoogle() async => sesion = true;

  @override
  Future<String> tokenDeAcceso() async => 'token-de-acceso';

  @override
  Future<void> cerrarSesion() async => sesion = false;
}
