/// Los outfits que propone el `recomendador` y como se reparten en la semana.
library;

import 'package:wearhack/core/vocabulario.dart';
import 'package:wearhack/features/closet/prenda.dart';
import 'package:wearhack/features/outfits/contexto.dart';

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
  final Clima? clima;

  /// Las prendas en el orden de [SlotOutfit], que es el orden en que se viste.
  List<Prenda> get prendasEnOrden => <Prenda>[
    for (final SlotOutfit slot in SlotOutfit.values)
      if (prendas[slot] case final Prenda prenda) prenda,
  ];
}

/// Las opciones entre las que el usuario elige el outfit de un dia.
///
/// Son N = 3, distintas entre si en al menos dos prendas principales
/// (respuestas D.27). Lo elegido frente a lo descartado del mismo lote es la
/// senal con la que el job nocturno ajusta las preferencias (D.26): no hay un
/// "me gusta" aparte.
class LoteOpciones {
  const LoteOpciones({
    required this.id,
    required this.fecha,
    required this.contexto,
    required this.opciones,
    this.elegidoId,
    this.elegido,
  });

  final String id;

  /// Medianoche local del dia para el que se proponen.
  final DateTime fecha;

  /// Con que ocasion, mood y clima se generaron las opciones.
  final ContextoOutfit contexto;

  final List<Outfit> opciones;

  /// Lo que ya se eligio hoy. Un dia da una sola seleccion: elegir dos veces
  /// contaria doble la misma comparacion, aunque se cambie el contexto.
  final String? elegidoId;

  /// El outfit de [elegidoId]. Puede faltar aunque haya eleccion, si despues
  /// se elimino una de sus prendas.
  final Outfit? elegido;
}

/// Un dia del plan semanal. Sin outfit es un dia libre.
class DiaPlan {
  const DiaPlan({required this.fecha, this.outfit});

  /// Medianoche local del dia.
  final DateTime fecha;
  final Outfit? outfit;
}
