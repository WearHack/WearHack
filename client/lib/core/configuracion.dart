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

  static const String version = '0.1.0';
}
