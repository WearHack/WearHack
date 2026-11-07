/// El resultado de la colorimetria: lo que el Core devuelve y guarda. El recorte
/// facial no esta aqui ni en ningun otro sitio: nunca se persiste.
library;

import 'dart:typed_data';

import 'package:wearhack/core/vocabulario.dart';

class PerfilColorimetria {
  const PerfilColorimetria({
    required this.temporada,
    required this.confianza,
    required this.piel,
    required this.cabello,
    required this.iris,
    required this.ejes,
    required this.calculadoEn,
  });

  factory PerfilColorimetria.desdeJson(Map<String, dynamic> json) =>
      PerfilColorimetria(
        temporada: json['temporada'] as String?,
        confianza: (json['confianza'] as num?)?.toDouble(),
        piel: _lab(json['piel']),
        cabello: _lab(json['cabello']),
        iris: _lab(json['iris']),
        ejes: <String>[
          for (final Object? e in (json['ejes'] as List<Object?>? ?? const []))
            e as String,
        ],
        calculadoEn: json['calculadoEn'] == null
            ? null
            : DateTime.parse(json['calculadoEn'] as String),
      );

  /// El nombre de la temporada tal como lo manda el servicio, o `null` si el
  /// servicio no se atrevio a clasificar.
  final String? temporada;

  /// De 0 a 1.
  final double? confianza;

  final ColorLab? piel;
  final ColorLab? cabello;
  final ColorLab? iris;

  /// Los ejes de la clasificacion que se usaron (subtono, valor, croma...).
  final List<String> ejes;

  final DateTime? calculadoEn;

  static ColorLab? _lab(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return ColorLab(
      l: (json['l'] as num).toDouble(),
      a: (json['a'] as num).toDouble(),
      b: (json['b'] as num).toDouble(),
    );
  }
}

/// Analizar el recorte facial y administrar el resultado.
abstract interface class ServicioColorimetria {
  /// Manda el recorte (PNG) y devuelve el perfil calculado. Requiere un
  /// consentimiento vigente: sin el, el Core responde 422.
  ///
  /// Es el unico camino por el que algo de la cara sale del telefono, y solo
  /// lleva el recorte (ADR 0016).
  Future<PerfilColorimetria> analizar(Uint8List png);

  /// El perfil guardado, o `null` si no hay.
  Future<PerfilColorimetria?> perfil();

  /// Borra el perfil. El consentimiento sigue vigente.
  Future<void> borrarPerfil();
}
