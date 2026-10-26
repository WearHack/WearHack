/// Configuracion de Amplify armada con los valores de --dart-define.
///
/// Amplify suele leerla de un amplify_outputs.json generado por su CLI. Aqui no
/// hay CLI de Amplify (el pool se crea a mano, ver infra/cognito/README.md), y
/// asi cada quien apunta a su Learner Lab sin tocar archivos versionados.
library;

import 'dart:convert';

/// Esquema y vuelta a la app despues de la Hosted UI. Tienen que coincidir con
/// las callback URLs del app client y con el intent-filter de Android.
const String redireccionInicio = 'wearhack://auth/';
const String redireccionSalida = 'wearhack://signout/';

/// El JSON de amplify_outputs (version 1) solo con la parte de autenticacion.
///
/// Sin [dominio] no hay Hosted UI y, por tanto, no hay entrada con Google: solo
/// correo y contrasena.
String salidasAmplify({
  required String region,
  required String userPoolId,
  required String clientId,
  String dominio = '',
}) {
  final Map<String, Object> auth = <String, Object>{
    'aws_region': region,
    'user_pool_id': userPoolId,
    'user_pool_client_id': clientId,
    'username_attributes': <String>['email'],
    'standard_required_attributes': <String>['email'],
    'user_verification_types': <String>['email'],
    'unauthenticated_identities_enabled': false,
    'password_policy': <String, Object>{
      'min_length': 8,
      'require_lowercase': true,
      'require_uppercase': true,
      'require_numbers': true,
      'require_symbols': false,
    },
  };
  if (dominio.isNotEmpty) {
    auth['oauth'] = <String, Object>{
      'identity_providers': <String>['GOOGLE'],
      'domain': dominio,
      'scopes': <String>[
        'openid',
        'email',
        'profile',
        'aws.cognito.signin.user.admin',
      ],
      'redirect_sign_in_uri': <String>[redireccionInicio],
      'redirect_sign_out_uri': <String>[redireccionSalida],
      'response_type': 'code',
    };
  }
  return jsonEncode(<String, Object>{'version': '1', 'auth': auth});
}
