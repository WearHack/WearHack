/// Controles de calidad del recorte (protocolo, seccion 2, nivel 0).
///
/// Siempre se **miden**. Solo se marcan como fallidos si hay un umbral en la
/// [ConfiguracionRecorte], y los umbrales no estan definidos: se fijaran con
/// los datos de la sesion de calibracion. Fallar un control nunca bloquea; la
/// app sugiere repetir la foto con una recomendacion concreta.
///
/// Las medidas se hacen sobre el recorte completo ya en sRGB, no solo sobre la
/// piel: separar la piel exige la segmentacion de MediaPipe, que corre en el
/// servidor.
library;

import 'dart:typed_data';

import 'package:wearhack/core/recorte/configuracion_recorte.dart';

/// Un control que no paso, con lo que se le dice a la persona.
enum ControlCalidad {
  rostroPequeno('Acerca el celular un poco: el rostro se ve muy chico.'),
  demasiadosQuemados(
    'Hay zonas con demasiada luz: busca una luz mas suave y evita el sol '
    'directo en la cara.',
  ),
  demasiadosNegros(
    'Hay zonas muy oscuras: busca una luz mas fuerte, por ejemplo frente a una '
    'ventana.',
  ),
  desenfocado(
    'La foto salio borrosa: sostiene el celular firme y espera a que enfoque.',
  );

  const ControlCalidad(this.recomendacion);

  final String recomendacion;
}

class ControlesCalidad {
  const ControlesCalidad({
    required this.anchoRostroPx,
    required this.porcentajeQuemados,
    required this.porcentajeNegros,
    required this.nitidez,
    required this.fallidos,
  });

  /// Ancho del rostro en pixeles de la foto completa y orientada.
  final int anchoRostroPx;

  /// Porcentaje de pixeles con algun canal en 255 (recortados por saturacion).
  /// Es una definicion estricta a proposito: no hay corte arbitrario.
  final double porcentajeQuemados;

  /// Porcentaje de pixeles con los tres canales en 0.
  final double porcentajeNegros;

  /// Varianza del laplaciano de la luminancia. Mas alto es mas nitido. Depende
  /// de la resolucion: comparar siempre junto con el ancho del recorte.
  final double nitidez;

  /// Controles con umbral que no se cumplieron. Vacio si pasan todos, o si no
  /// hay umbrales configurados.
  final List<ControlCalidad> fallidos;

  bool get pasa => fallidos.isEmpty;

  /// Las recomendaciones de los controles fallidos, listas para mostrar.
  List<String> get recomendaciones => <String>[
    for (final ControlCalidad c in fallidos) c.recomendacion,
  ];
}

/// Mide los controles sobre `rgb` (3 bytes por pixel, empaquetado, en sRGB).
ControlesCalidad medirCalidad(
  Uint8List rgb, {
  required int ancho,
  required int alto,
  required int anchoRostroPx,
  required ConfiguracionRecorte configuracion,
}) {
  assert(rgb.length == ancho * alto * 3);
  final int pixeles = ancho * alto;

  int quemados = 0;
  int negros = 0;
  final Uint8List luma = Uint8List(pixeles);
  for (int p = 0, i = 0; p < pixeles; p++, i += 3) {
    final int r = rgb[i], g = rgb[i + 1], b = rgb[i + 2];
    if (r == 255 || g == 255 || b == 255) quemados++;
    if (r == 0 && g == 0 && b == 0) negros++;
    luma[p] = (r * 299 + g * 587 + b * 114) ~/ 1000;
  }

  final double pctQuemados = pixeles == 0 ? 0 : quemados * 100 / pixeles;
  final double pctNegros = pixeles == 0 ? 0 : negros * 100 / pixeles;
  final double nitidez = _varianzaDelLaplaciano(luma, ancho, alto);

  final List<ControlCalidad> fallidos = <ControlCalidad>[
    if (configuracion.anchoMinimoRostroPx != null &&
        anchoRostroPx < configuracion.anchoMinimoRostroPx!)
      ControlCalidad.rostroPequeno,
    if (configuracion.maxQuemadosPct != null &&
        pctQuemados > configuracion.maxQuemadosPct!)
      ControlCalidad.demasiadosQuemados,
    if (configuracion.maxNegrosPct != null &&
        pctNegros > configuracion.maxNegrosPct!)
      ControlCalidad.demasiadosNegros,
    if (configuracion.nitidezMinima != null &&
        nitidez < configuracion.nitidezMinima!)
      ControlCalidad.desenfocado,
  ];

  return ControlesCalidad(
    anchoRostroPx: anchoRostroPx,
    porcentajeQuemados: pctQuemados,
    porcentajeNegros: pctNegros,
    nitidez: nitidez,
    fallidos: fallidos,
  );
}

double _varianzaDelLaplaciano(Uint8List luma, int ancho, int alto) {
  if (ancho < 3 || alto < 3) return 0;
  double suma = 0;
  double sumaDeCuadrados = 0;
  int n = 0;
  for (int y = 1; y < alto - 1; y++) {
    final int fila = y * ancho;
    for (int x = 1; x < ancho - 1; x++) {
      final int i = fila + x;
      final int l =
          4 * luma[i] -
          luma[i - 1] -
          luma[i + 1] -
          luma[i - ancho] -
          luma[i + ancho];
      suma += l;
      sumaDeCuadrados += l * l;
      n++;
    }
  }
  final double media = suma / n;
  return sumaDeCuadrados / n - media * media;
}
