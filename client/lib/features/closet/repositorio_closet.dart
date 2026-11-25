/// Lo que las pantallas del closet necesitan del backend.
///
library;

import 'package:wearhack/features/closet/prenda.dart';

abstract interface class RepositorioCloset {
  Future<List<Prenda>> prendas();
}

abstract interface class ClosetConBorrado implements RepositorioCloset {
  /// Quita la prenda del closet. Los outfits que la usaban dejan de valer.
  Future<void> eliminarPrenda(String id);
}
