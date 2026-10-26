/// Registro e inicio de sesion contra Cognito.
///
/// Las pantallas hablan con [Autenticacion] y no con Amplify, para poder
/// probarlas sin un User Pool de verdad.
library;

import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:wearhack/features/cuenta/configuracion_cognito.dart';

abstract class Autenticacion {
  Future<bool> haySesion();

  /// Crea la cuenta. Cognito manda un codigo al correo, que se confirma con
  /// [confirmarRegistro].
  Future<void> registrarse(String correo, String clave);

  Future<void> confirmarRegistro(String correo, String codigo);

  Future<void> iniciarSesion(String correo, String clave);

  /// Hosted UI de Cognito con Google, en Custom Tabs en Android.
  Future<void> iniciarConGoogle();

  /// Si no hay dominio de Hosted UI configurado, no se ofrece Google.
  bool get googleDisponible;

  /// El token de acceso que espera el Core. Nunca el de identidad: el Core lo
  /// rechaza.
  Future<String> tokenDeAcceso();

  Future<void> cerrarSesion();
}

/// Un fallo que se puede mostrar tal cual a la persona.
class ErrorDeAutenticacion implements Exception {
  ErrorDeAutenticacion(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}

class AutenticacionAmplify implements Autenticacion {
  AutenticacionAmplify({required this.googleDisponible});

  @override
  final bool googleDisponible;

  /// Se llama una vez, antes de pintar la app.
  static Future<AutenticacionAmplify> configurar({
    required String region,
    required String userPoolId,
    required String clientId,
    required String dominio,
  }) async {
    if (!Amplify.isConfigured) {
      await Amplify.addPlugin(AmplifyAuthCognito());
      await Amplify.configure(
        salidasAmplify(
          region: region,
          userPoolId: userPoolId,
          clientId: clientId,
          dominio: dominio,
        ),
      );
    }
    return AutenticacionAmplify(googleDisponible: dominio.isNotEmpty);
  }

  @override
  Future<bool> haySesion() async {
    final AuthSession sesion = await Amplify.Auth.fetchAuthSession();
    return sesion.isSignedIn;
  }

  @override
  Future<void> registrarse(String correo, String clave) => _traducir(() async {
    await Amplify.Auth.signUp(
      username: correo,
      password: clave,
      options: SignUpOptions(
        userAttributes: <AuthUserAttributeKey, String>{
          AuthUserAttributeKey.email: correo,
        },
      ),
    );
  });

  @override
  Future<void> confirmarRegistro(String correo, String codigo) =>
      _traducir(() async {
        await Amplify.Auth.confirmSignUp(
          username: correo,
          confirmationCode: codigo,
        );
      });

  @override
  Future<void> iniciarSesion(String correo, String clave) =>
      _traducir(() async {
        final SignInResult resultado = await Amplify.Auth.signIn(
          username: correo,
          password: clave,
        );
        if (!resultado.isSignedIn) {
          // Correo sin confirmar, MFA, cambio de clave: fuera del MVP.
          throw ErrorDeAutenticacion(
            'Falta un paso: ${resultado.nextStep.signInStep.name}',
          );
        }
      });

  @override
  Future<void> iniciarConGoogle() => _traducir(() async {
    await Amplify.Auth.signInWithWebUI(provider: AuthProvider.google);
  });

  @override
  Future<String> tokenDeAcceso() async {
    final CognitoAuthSession sesion = await Amplify.Auth.getPlugin(
      AmplifyAuthCognito.pluginKey,
    ).fetchAuthSession();
    return sesion.userPoolTokensResult.value.accessToken.raw;
  }

  @override
  Future<void> cerrarSesion() async {
    await Amplify.Auth.signOut();
  }

  static Future<void> _traducir(Future<void> Function() accion) async {
    try {
      await accion();
    } on AuthException catch (error) {
      throw ErrorDeAutenticacion(error.message);
    }
  }
}
