/// Parametros del recorte facial y de sus controles de calidad.
///
/// **Los margenes son PROVISIONALES.** `docs/respuestas-claude-code.md` (A.8 y
/// A.9) los dejaba "para fijar con los datos del protocolo"; hasta entonces se
/// usan los de [margenSuperiorProvisional], [margenInferiorProvisional] y
/// [margenLateralProvisional] (fracciones del tamano del rostro detectado),
/// fijados por el responsable de la spec el 2026-10 para la fase de captura. No
/// salen de ninguna medicion: se cambian al compilar sin tocar codigo.
///
///   flutter run ///     --dart-define=RECORTE_MARGEN_SUPERIOR=0.6 ///     --dart-define=RECORTE_MARGEN_INFERIOR=0.15 ///     --dart-define=RECORTE_MARGEN_LATERAL=0.3
///
/// Los umbrales de calidad siguen **sin definirse** y no traen valor: sin
/// umbral, el control se mide y se reporta, pero nunca se marca como fallido.
library;

/// La configuracion del recorte falta o tiene un valor invalido.
class ConfiguracionRecorteInvalida implements Exception {
  const ConfiguracionRecorteInvalida(this.problemas);

  /// Una frase por problema, con el nombre del `--dart-define` afectado.
  final List<String> problemas;

  @override
  String toString() =>
      'ConfiguracionRecorteInvalida: ${problemas.join('; ')}. '
      'Se pasan con --dart-define=NOMBRE=valor al compilar.';
}

/// Margenes provisionales. Ver la cabecera del archivo.
const double margenSuperiorProvisional = 0.6;
const double margenInferiorProvisional = 0.15;
const double margenLateralProvisional = 0.3;

class ConfiguracionRecorte {
  const ConfiguracionRecorte({
    required this.margenSuperior,
    required this.margenInferior,
    required this.margenLateral,
    this.anchoMinimoRostroPx,
    this.maxQuemadosPct,
    this.maxNegrosPct,
    this.nitidezMinima,
    this.ladoMaximoDeteccion = 1280,
  }) : assert(margenSuperior >= 0 && margenInferior >= 0 && margenLateral >= 0);

  /// Cuanto se agranda el recuadro del rostro, como fraccion de su alto (arriba
  /// y abajo) o de su ancho (a los lados). Arriba hace falta margen para que
  /// entre el cabello.
  final double margenSuperior;
  final double margenInferior;
  final double margenLateral;

  /// Ancho minimo del rostro, en pixeles de la foto completa y ya orientada.
  final int? anchoMinimoRostroPx;

  /// Porcentaje maximo de pixeles con algun canal en 255, de 0 a 100.
  final double? maxQuemadosPct;

  /// Porcentaje maximo de pixeles con los tres canales en 0, de 0 a 100.
  final double? maxNegrosPct;

  /// Varianza minima del laplaciano de la luminancia. Depende de la resolucion
  /// del recorte: se compara junto con el ancho del rostro.
  final double? nitidezMinima;

  /// Lado mayor, en pixeles, de la copia que se le da al detector. No es un
  /// valor de dominio sino de rendimiento: detectar un rostro no necesita los
  /// 12 megapixeles, y el recorte se hace siempre sobre la foto completa.
  final int ladoMaximoDeteccion;

  /// Lee la configuracion de los `--dart-define` del build. Los margenes que no
  /// se pasen valen los provisionales.
  factory ConfiguracionRecorte.desdeEntorno() =>
      ConfiguracionRecorte.desdeTextos(const <String, String>{
        'RECORTE_MARGEN_SUPERIOR': String.fromEnvironment(
          'RECORTE_MARGEN_SUPERIOR',
          defaultValue: '$margenSuperiorProvisional',
        ),
        'RECORTE_MARGEN_INFERIOR': String.fromEnvironment(
          'RECORTE_MARGEN_INFERIOR',
          defaultValue: '$margenInferiorProvisional',
        ),
        'RECORTE_MARGEN_LATERAL': String.fromEnvironment(
          'RECORTE_MARGEN_LATERAL',
          defaultValue: '$margenLateralProvisional',
        ),
        'RECORTE_ANCHO_MINIMO_ROSTRO_PX': String.fromEnvironment(
          'RECORTE_ANCHO_MINIMO_ROSTRO_PX',
        ),
        'CALIDAD_MAX_QUEMADOS_PCT': String.fromEnvironment(
          'CALIDAD_MAX_QUEMADOS_PCT',
        ),
        'CALIDAD_MAX_NEGROS_PCT': String.fromEnvironment(
          'CALIDAD_MAX_NEGROS_PCT',
        ),
        'CALIDAD_NITIDEZ_MINIMA': String.fromEnvironment(
          'CALIDAD_NITIDEZ_MINIMA',
        ),
      });

  /// Construye la configuracion desde textos. Separado de [desdeEntorno] para
  /// poder probarlo: `String.fromEnvironment` solo admite constantes.
  ///
  /// Un texto vacio cuenta como ausente.
  factory ConfiguracionRecorte.desdeTextos(Map<String, String> valores) {
    final List<String> problemas = <String>[];

    double? numero(String nombre, {required bool obligatorio, double? max}) {
      final String texto = (valores[nombre] ?? '').trim();
      if (texto.isEmpty) {
        if (obligatorio) problemas.add('falta $nombre');
        return null;
      }
      final double? v = double.tryParse(texto);
      if (v == null || !v.isFinite || v < 0 || (max != null && v > max)) {
        problemas.add(
          '$nombre="$texto" no es un numero valido'
          '${max != null ? ' entre 0 y ${max.toInt()}' : ' mayor o igual a 0'}',
        );
        return null;
      }
      return v;
    }

    final double? superior = numero(
      'RECORTE_MARGEN_SUPERIOR',
      obligatorio: true,
    );
    final double? inferior = numero(
      'RECORTE_MARGEN_INFERIOR',
      obligatorio: true,
    );
    final double? lateral = numero('RECORTE_MARGEN_LATERAL', obligatorio: true);
    final double? ancho = numero(
      'RECORTE_ANCHO_MINIMO_ROSTRO_PX',
      obligatorio: false,
    );
    final double? quemados = numero(
      'CALIDAD_MAX_QUEMADOS_PCT',
      obligatorio: false,
      max: 100,
    );
    final double? negros = numero(
      'CALIDAD_MAX_NEGROS_PCT',
      obligatorio: false,
      max: 100,
    );
    final double? nitidez = numero(
      'CALIDAD_NITIDEZ_MINIMA',
      obligatorio: false,
    );

    if (problemas.isNotEmpty) throw ConfiguracionRecorteInvalida(problemas);

    return ConfiguracionRecorte(
      margenSuperior: superior!,
      margenInferior: inferior!,
      margenLateral: lateral!,
      anchoMinimoRostroPx: ancho?.round(),
      maxQuemadosPct: quemados,
      maxNegrosPct: negros,
      nitidezMinima: nitidez,
    );
  }
}
