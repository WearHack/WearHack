/// Guia de distancia: dice si el rostro esta a los 30-40 cm del protocolo.
///
/// Se basa en el ancho del rostro que detecta ML Kit en el fotograma de
/// analisis. Ese ancho en pixeles equivale a una distancia distinta en cada
/// celular, asi que el rango que corresponde a 30-40 cm **se calibra una vez por
/// celular** (spec, 3.3). Ese rango **no esta definido todavia**: no hay un valor
/// por defecto. Mientras falte, la guia dice "sin calibrar" y muestra el ancho
/// que mide, que es justo lo que hace falta para calibrar: se pone el rostro a
/// 30-40 cm, se anota el numero, y se pasa al compilar:
///
///   --dart-define=DISTANCIA_ANCHO_D2=380-520
///
/// (el numero es solo un ejemplo de formato.)
library;

import 'package:wearhack/features/captura_pruebas/modelos.dart';

enum EstadoDeDistancia { sinCalibrar, sinRostro, muyLejos, bien, muyCerca }

/// Rango de ancho de rostro, en pixeles del fotograma de analisis, que equivale
/// a 30-40 cm.
class RangoDeAncho {
  const RangoDeAncho({required this.minimo, required this.maximo})
    : assert(minimo > 0 && maximo >= minimo);

  /// A este ancho o mas pequeno, el rostro esta demasiado lejos.
  final int minimo;

  /// A este ancho o mas grande, el rostro esta demasiado cerca.
  final int maximo;

  /// Lee `"380-520"`. Devuelve `null` si esta vacio o no tiene esa forma.
  static RangoDeAncho? desdeTexto(String texto) {
    final RegExpMatch? m = RegExp(r'^\s*(\d+)\s*-\s*(\d+)\s*$')
        .firstMatch(texto);
    if (m == null) return null;
    final int min = int.parse(m.group(1)!);
    final int max = int.parse(m.group(2)!);
    if (min <= 0 || max < min) return null;
    return RangoDeAncho(minimo: min, maximo: max);
  }
}

/// Clasifica el ancho medido contra el rango del celular.
///
/// [ancho] `null` significa que no se ve ningun rostro. Sin [rango] no se puede
/// decir nada sobre la distancia ([EstadoDeDistancia.sinCalibrar]).
EstadoDeDistancia clasificarDistancia(int? ancho, RangoDeAncho? rango) {
  if (rango == null) return EstadoDeDistancia.sinCalibrar;
  if (ancho == null) return EstadoDeDistancia.sinRostro;
  if (ancho < rango.minimo) return EstadoDeDistancia.muyLejos;
  if (ancho > rango.maximo) return EstadoDeDistancia.muyCerca;
  return EstadoDeDistancia.bien;
}

/// El rango calibrado de un celular, de los `--dart-define`, o `null`.
RangoDeAncho? rangoDeDistanciaDelEntorno(CodigoCelular celular) =>
    RangoDeAncho.desdeTexto(switch (celular) {
      CodigoCelular.d1 => const String.fromEnvironment('DISTANCIA_ANCHO_D1'),
      CodigoCelular.d2 => const String.fromEnvironment('DISTANCIA_ANCHO_D2'),
      CodigoCelular.d3 => const String.fromEnvironment('DISTANCIA_ANCHO_D3'),
    });

/// El texto que ve la persona para cada estado.
String textoDeDistancia(EstadoDeDistancia estado, int? ancho) =>
    switch (estado) {
      EstadoDeDistancia.sinCalibrar =>
        'Distancia sin calibrar para este celular'
            '${ancho != null ? ' (rostro: $ancho px)' : ''}',
      EstadoDeDistancia.sinRostro => 'No se ve un rostro',
      EstadoDeDistancia.muyLejos => 'Acercate un poco (30-40 cm)',
      EstadoDeDistancia.bien => 'Distancia correcta',
      EstadoDeDistancia.muyCerca => 'Alejate un poco (30-40 cm)',
    };
