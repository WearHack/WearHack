/// Lo que las pantallas de marcas aliadas necesitan del backend.
///
/// Hoy lo implementa el repositorio falso de `lib/mock/`. La version real
/// llamara al gateway (`/api/v1/publicidad/...`). El ranking lo calcula un job
/// nocturno del recomendador; Publicidad solo lo lee.
library;

import 'package:wearhack/features/publicidad/catalogo.dart';

abstract interface class RepositorioPublicidad {
  Future<List<MarcaAliada>> marcas();

  Future<List<ProductoCatalogo>> catalogo(String marcaId);

  /// Las prendas puente del usuario, ya ordenadas: primero la que mas
  /// combinaciones abre. Solo las que llegan a [umbralPrendaPuente].
  Future<List<PrendaPuente>> prendasPuente();
}
