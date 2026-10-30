/// Cuando esta el telefono demasiado caliente para seguir procesando (issue #11).
///
/// La regla vive aqui, sin plugin, para poder probarla. El plugin `thermal` se
/// conecta en `platform/captura/captura_movil.dart`, que traduce sus valores a
/// [NivelTermico] y a grados de bateria.
///
/// - Android 10 o superior da el estado termico del sistema: es la senal buena,
///   la misma que usa el sistema para bajar el rendimiento.
/// - Android 8 y 9 (seguimos soportando desde minSdk 26) solo dan la temperatura
///   de la bateria. Es una aproximacion, y por eso solo cuenta mientras no haya
///   llegado ningun estado del sistema.
///
/// **Los umbrales son provisionales**: la spec dice "pausa si el celular se
/// calienta" sin numero. Se cambian al compilar, ver [UmbralTermico.desdeEntorno].
library;

import 'dart:async';

import 'package:wearhack/features/closet/captura/cola_captura.dart';

/// Los niveles del estado termico de Android (`PowerManager.THERMAL_STATUS_*`),
/// en orden. `ninguno` tambien es lo que reportan los equipos que no lo soportan.
enum NivelTermico {
  ninguno,
  leve,
  moderado,
  severo,
  critico,
  emergencia,
  apagado,
}

class UmbralTermico {
  const UmbralTermico({
    this.nivelDePausa = NivelTermico.severo,
    this.bateriaMaximaC = 42,
  });

  /// Lee los umbrales de los `--dart-define`. Los que falten o no se entiendan
  /// valen los provisionales:
  ///
  ///   --dart-define=TERMICO_NIVEL_PAUSA=moderado
  ///   --dart-define=TERMICO_BATERIA_MAX_C=40
  factory UmbralTermico.desdeEntorno() => UmbralTermico.desdeTextos(
    nivel: const String.fromEnvironment('TERMICO_NIVEL_PAUSA'),
    bateria: const String.fromEnvironment('TERMICO_BATERIA_MAX_C'),
  );

  factory UmbralTermico.desdeTextos({String nivel = '', String bateria = ''}) {
    const UmbralTermico defecto = UmbralTermico();
    final NivelTermico? leido = NivelTermico.values
        .where((NivelTermico n) => n.name == nivel.trim().toLowerCase())
        .firstOrNull;
    final double? grados = double.tryParse(bateria.trim());
    return UmbralTermico(
      nivelDePausa: leido ?? defecto.nivelDePausa,
      bateriaMaximaC: grados != null && grados.isFinite
          ? grados
          : defecto.bateriaMaximaC,
    );
  }

  /// Desde este nivel se pausa. `severo` es donde Android ya recorta el
  /// rendimiento de forma visible; en `moderado` todavia se puede trabajar.
  final NivelTermico nivelDePausa;

  /// Solo para Android 8 y 9. A partir de esta temperatura de bateria, se pausa.
  final double bateriaMaximaC;
}

/// El estado termico del telefono, a partir de los avisos del sistema.
///
/// La cola pregunta [caliente] de forma sincrona en cada ronda, asi que aqui se
/// guarda el ultimo valor de cada stream. Un stream que falla deja de contar:
/// un sensor roto no debe parar la captura.
class EstadoTermicoDispositivo implements EstadoTermico {
  EstadoTermicoDispositivo({
    required Stream<NivelTermico> niveles,
    required Stream<double> temperaturasBateria,
    this.umbral = const UmbralTermico(),
  }) {
    _suscripciones = <StreamSubscription<Object?>>[
      niveles.listen(
        (NivelTermico n) => _nivel = n,
        onError: (Object _) => _nivel = null,
      ),
      temperaturasBateria.listen(
        (double t) => _bateria = t,
        onError: (Object _) => _bateria = null,
      ),
    ];
  }

  final UmbralTermico umbral;
  late final List<StreamSubscription<Object?>> _suscripciones;
  NivelTermico? _nivel;
  double? _bateria;

  /// El ultimo nivel del sistema, o `null` si no ha llegado ninguno.
  NivelTermico? get nivel => _nivel;

  /// La ultima temperatura de bateria en grados C, o `null`.
  double? get bateriaC => _bateria;

  @override
  bool get caliente {
    final NivelTermico? nivel = _nivel;
    // `ninguno` lo reportan tambien los equipos sin soporte (Android 8 y 9):
    // ahi manda la bateria.
    if (nivel != null && nivel != NivelTermico.ninguno) {
      return nivel.index >= umbral.nivelDePausa.index;
    }
    final double? bateria = _bateria;
    return bateria != null && bateria >= umbral.bateriaMaximaC;
  }

  Future<void> cerrar() async {
    for (final StreamSubscription<Object?> s in _suscripciones) {
      await s.cancel();
    }
  }
}
