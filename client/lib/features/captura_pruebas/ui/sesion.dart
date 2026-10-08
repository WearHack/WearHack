/// Los datos que se eligen una vez al empezar y valen para toda la sesion.
library;

import 'package:wearhack/features/captura_pruebas/modelos.dart';

class SesionCaptura {
  const SesionCaptura({
    required this.seudonimo,
    required this.celular,
    required this.autorizacionFirmada,
    required this.trueToneONightShift,
  });

  /// Quien se esta fotografiando. Nunca un nombre real: `P1` a `P6`.
  final Seudonimo seudonimo;

  /// Con que celular se toman las fotos.
  final CodigoCelular celular;

  /// La casilla "Autorizacion de calibracion firmada". Sin ella, no hay captura.
  final bool autorizacionFirmada;

  /// iOS no permite leer True Tone ni Night Shift: lo marca la persona.
  final bool trueToneONightShift;
}
