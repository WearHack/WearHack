/// Configuracion del cliente, fijada al compilar.
///
/// Se pasa con --dart-define para no tener que recompilar el codigo por cambiar
/// de entorno:
///
///   flutter build apk --dart-define=API_BASE=https://api.wearhack.app
class Configuracion {
  const Configuracion._();

  /// Raiz del API. Todo pasa por el gateway; el cliente no conoce los
  /// servicios de detras ni sus puertos.
  ///
  /// El valor por defecto apunta al gateway del docker compose visto desde el
  /// emulador de Android, donde 10.0.2.2 es el equipo anfitrion.
  static const String apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://10.0.2.2:8080',
  );

  /// Activa el modo de captura de pruebas (calibracion de colorimetria).
  ///
  /// Solo para builds internas: `--dart-define=CAPTURA_PRUEBAS=true`. Sin el
  /// flag el modo no existe: no hay ruta, menu ni gesto que lo abra, y como el
  /// codigo solo se alcanza detras de esta constante, el compilador lo descarta.
  static const bool capturaPruebas = bool.fromEnvironment('CAPTURA_PRUEBAS');

  /// Enciende la guia de distancia en vivo del modo de captura de pruebas.
  ///
  /// Apagada por defecto: depende de pasar fotogramas de la camara a ML Kit, y
  /// eso no se ha verificado en un telefono. Ver `CamaraDeCaptura`.
  static const bool capturaGuiaEnVivo = bool.fromEnvironment(
    'CAPTURA_GUIA_EN_VIVO',
  );

  /// Enciende la captura de prendas en cola (issue #11): el boton "Agregar
  /// prendas" del closet y la cola en segundo plano.
  ///
  /// `--dart-define=CAPTURA_PRENDAS=true` la enciende en móvil. Los modelos
  /// deben estar incluidos en la build y la subida al Core requiere sesión.
  static const bool capturaPrendas = bool.fromEnvironment('CAPTURA_PRENDAS');

  /// Raiz del Core (perfil, consentimientos). El Core no va detras del gateway:
  /// en el docker compose se le pega directo, y la ruta /api/v1/usuarios del
  /// gateway todavia apunta al servicio viejo, que solo tiene /health.
  static const String coreBase = String.fromEnvironment(
    'CORE_BASE',
    defaultValue: 'http://10.0.2.2:8090',
  );

  /// El User Pool de Cognito. Sin pool ni app client la app arranca sin
  /// pantalla de acceso, como hasta ahora. Ver infra/cognito/README.md.
  static const String cognitoRegion = String.fromEnvironment(
    'COGNITO_REGION',
    defaultValue: 'us-east-1',
  );
  static const String cognitoUserPoolId = String.fromEnvironment(
    'COGNITO_USER_POOL_ID',
  );
  static const String cognitoClientId = String.fromEnvironment(
    'COGNITO_CLIENT_ID',
  );

  /// Dominio de la Hosted UI, sin https://. Hace falta para entrar con Google.
  static const String cognitoDominio = String.fromEnvironment(
    'COGNITO_DOMINIO',
  );

  static const bool cognitoConfigurado =
      cognitoUserPoolId != '' && cognitoClientId != '';

  static const String version = '0.1.0';
}
