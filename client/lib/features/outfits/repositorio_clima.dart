/// De donde sale la temperatura para elegir la banda de clima.
///
/// Sin decidir todavia: no esta definido si el clima lo consulta el cliente o
/// el backend, ni con que proveedor. Hoy lo simula el repositorio falso.
library;

abstract interface class RepositorioClima {
  /// La temperatura actual en grados Celsius, o `null` si no hay dato.
  Future<double?> temperaturaEn({
    required double latitud,
    required double longitud,
  });
}
