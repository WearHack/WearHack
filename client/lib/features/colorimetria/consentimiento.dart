/// La autorizacion para analizar el recorte facial.
///
/// Politica de datos, seccion 5: pantalla propia antes de la camara, sin
/// casilla premarcada, separada de los terminos, con opcion visible de omitir
/// y **versionada**. Si el texto o la finalidad cambian, una autorizacion dada
/// sobre la version anterior deja de valer y hay que volver a pedirla.
library;

/// La version del texto de `ui/texto_consentimiento.dart`.
///
/// **Si cambias ese texto, sube este numero.** Un test compara el texto con su
/// huella y falla si cambia sin que la version suba.
const int versionTextoConsentimiento = 1;

enum DecisionConsentimiento { autorizo, omitio }

class Consentimiento {
  const Consentimiento({
    required this.decision,
    required this.version,
    required this.fecha,
  });

  final DecisionConsentimiento decision;

  /// La version del texto que el usuario vio al decidir.
  final int version;

  final DateTime fecha;

  /// Si permite capturar hoy: autorizado y sobre el texto vigente.
  bool get vigente =>
      decision == DecisionConsentimiento.autorizo &&
      version == versionTextoConsentimiento;

  /// Autorizo, pero sobre un texto que ya cambio.
  bool get desactualizado =>
      decision == DecisionConsentimiento.autorizo &&
      version != versionTextoConsentimiento;
}
