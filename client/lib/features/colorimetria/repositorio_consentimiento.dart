/// Donde vive la decision de consentimiento del usuario.
///
/// Hoy lo implementa el repositorio falso de `lib/mock/`. La version real hablara
/// con el modulo Usuarios, que antes de reenviar un recorte a Colorimetria
/// comprueba que haya un consentimiento vigente (politica, seccion 4).
library;

import 'package:wearhack/features/colorimetria/consentimiento.dart';

abstract interface class RepositorioConsentimiento {
  /// La ultima decision, o `null` si nunca decidio o revoco.
  Future<Consentimiento?> consentimientoColorimetria();

  /// Registra que el usuario autorizo u omitio, sobre el texto [version].
  Future<void> registrar(DecisionConsentimiento decision, int version);

  /// Revoca la autorizacion. El backend borra ademas el perfil de color
  /// derivado (politica, seccion 7).
  Future<void> revocar();
}
