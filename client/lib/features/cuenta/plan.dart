/// El plan del usuario (Gratis, Esencial o Plus) y su cuota de IA del mes.
///
/// Lo decide el Core: la app solo lo muestra. Un plan que la app no conozca
/// (uno nuevo del Core) se trata como gratis, que es lo mas restrictivo.
library;

enum Plan {
  gratis('Gratis'),
  esencial('Esencial'),
  plus('Plus');

  const Plan(this.nombre);

  /// Como se le muestra al usuario.
  final String nombre;

  static Plan desdeCore(Object? valor) => switch (valor) {
    'ESENCIAL' => Plan.esencial,
    'PLUS' => Plan.plus,
    _ => Plan.gratis,
  };
}

/// Lo que permite el plan. `null` en un tope es ilimitado.
class DerechosPlan {
  const DerechosPlan({
    required this.solicitudesIaPorMes,
    required this.maxPrendas,
    required this.dressCodesPorMes,
    required this.escaneoEnTienda,
    required this.analisisDelCloset,
    required this.maleta,
  });

  factory DerechosPlan.desdeJson(Map<String, dynamic> json) => DerechosPlan(
    solicitudesIaPorMes: json['solicitudesIaPorMes'] as int,
    maxPrendas: json['maxPrendas'] as int?,
    dressCodesPorMes: json['dressCodesPorMes'] as int?,
    escaneoEnTienda: json['escaneoEnTienda'] as bool? ?? false,
    analisisDelCloset: json['analisisDelCloset'] as bool? ?? false,
    maleta: json['maleta'] as bool? ?? false,
  );

  final int solicitudesIaPorMes;
  final int? maxPrendas;
  final int? dressCodesPorMes;
  final bool escaneoEnTienda;
  final bool analisisDelCloset;
  final bool maleta;
}

/// `GET /api/v1/usuarios/me/plan`.
class EstadoPlan {
  const EstadoPlan({
    required this.plan,
    required this.derechos,
    required this.solicitudesIaUsadas,
    required this.solicitudesIaRestantes,
  });

  factory EstadoPlan.desdeJson(Map<String, dynamic> json) => EstadoPlan(
    plan: Plan.desdeCore(json['plan']),
    derechos: DerechosPlan.desdeJson(json['derechos'] as Map<String, dynamic>),
    solicitudesIaUsadas: json['solicitudesIaUsadas'] as int,
    solicitudesIaRestantes: json['solicitudesIaRestantes'] as int,
  );

  final Plan plan;
  final DerechosPlan derechos;
  final int solicitudesIaUsadas;
  final int solicitudesIaRestantes;

  bool get cuotaAgotada => solicitudesIaRestantes <= 0;
}
