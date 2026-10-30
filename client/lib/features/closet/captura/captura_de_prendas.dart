/// Lo que necesita la captura de prendas, ya conectado (issue #11).
///
/// Lo arma la plataforma (`abrirCapturaDePrendas` en `platform/captura.dart`) y
/// lo usa la UI. La cola y la pantalla comparten el mismo [termico]: el aviso de
/// la pantalla dice exactamente lo que la cola esta haciendo.
library;

import 'package:wearhack/features/closet/captura/cola_captura.dart';
import 'package:wearhack/platform/captura/camara.dart';

class CapturaDePrendas {
  const CapturaDePrendas({
    required this.cola,
    required this.termico,
    required this.crearCamara,
  });

  final ColaCaptura cola;
  final EstadoTermico termico;
  final CamaraDeCaptura Function() crearCamara;
}
