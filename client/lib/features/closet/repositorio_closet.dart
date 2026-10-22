/// Lo que las pantallas del closet necesitan del backend.
///
/// Hoy lo implementa el repositorio falso de `lib/mock/`, con datos en memoria.
/// La version real llamara al gateway (`/api/v1/closet/...`) y las pantallas no
/// tendran que cambiar.
library;

import 'package:wearhack/features/closet/prenda.dart';

abstract interface class RepositorioCloset {
  Future<List<Prenda>> prendas();

  /// Quita la prenda del closet. Los outfits que la usaban dejan de valer.
  Future<void> eliminarPrenda(String id);
}
