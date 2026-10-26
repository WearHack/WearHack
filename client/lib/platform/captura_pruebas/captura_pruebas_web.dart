/// El modo de captura de pruebas no existe en web.
///
/// Es la rama que toma la build de web. Su valor esta en lo que **no** importa:
/// ni camara, ni ML Kit, ni `dart:io`. Si algo de eso acabara en el bundle de
/// web, es que un import se colo fuera de esta frontera.
library;

import 'package:flutter/widgets.dart';
import 'package:wearhack/platform/captura/camara.dart';
import 'package:wearhack/platform/captura/contratos.dart';

Future<void> abrirCapturaPruebas(BuildContext context) async {
  throw const CapturaNoDisponible(
    'El modo de captura de pruebas solo corre en movil.',
  );
}

/// En web no hay camara: la UI consulta `FaceCropper.disponible` antes de llegar
/// aqui, asi que esto solo se ejecuta si alguien se salta esa comprobacion.
CamaraDeCaptura crearCamaraFrontal() {
  throw const CapturaNoDisponible('La camara solo existe en movil.');
}
