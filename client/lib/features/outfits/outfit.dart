/// Los outfits que propone el `recomendador` y como se reparten en la semana.
library;

import 'package:wearhack/core/vocabulario.dart';
import 'package:wearhack/features/closet/prenda.dart';

class Outfit {
  const Outfit({
    required this.id,
    required this.prendas,
    required this.formalidad,
    required this.clima,
  });

  final String id;

  /// Una prenda por slot. Un slot que no esta es un hueco, no un error: un
  /// vestido ocupa `cuerpoEntero` y deja vacios `superior` e `inferior`.
  final Map<SlotOutfit, Prenda> prendas;

  final Formalidad formalidad;
  final Clima clima;

  /// Las prendas en el orden de [SlotOutfit], que es el orden en que se viste.
  List<Prenda> get prendasEnOrden => <Prenda>[
    for (final SlotOutfit slot in SlotOutfit.values)
      if (prendas[slot] case final Prenda prenda) prenda,
  ];
}

/// Un dia del plan semanal. Sin outfit es un dia libre.
class DiaPlan {
  const DiaPlan({required this.fecha, this.outfit});

  /// Medianoche local del dia.
  final DateTime fecha;
  final Outfit? outfit;
}
