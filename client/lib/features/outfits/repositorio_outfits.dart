/// Lo que las pantallas de outfits y de la semana necesitan del backend.
///
/// Hoy lo implementa el repositorio falso de `lib/mock/`. La version real
/// llamara al gateway (`/api/v1/outfits/...`).
library;

import 'package:wearhack/features/outfits/outfit.dart';

abstract interface class RepositorioOutfits {
  /// Los outfits generados para la semana en curso.
  Future<List<Outfit>> outfitsDeLaSemana();

  /// Los siete dias de la semana en curso, de lunes a domingo.
  Future<List<DiaPlan>> planSemanal();

  /// Asigna [outfitId] a [dia]. Con `null` el dia queda libre.
  Future<void> asignarOutfit(DateTime dia, String? outfitId);
}
