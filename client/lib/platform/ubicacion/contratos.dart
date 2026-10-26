/// Lo que la app necesita de la ubicacion del dispositivo: nada mas que la
/// posicion aproximada para saber el clima.
library;

sealed class ResultadoUbicacion {
  const ResultadoUbicacion();
}

class UbicacionObtenida extends ResultadoUbicacion {
  const UbicacionObtenida({required this.latitud, required this.longitud});

  final double latitud;
  final double longitud;
}

/// El usuario no dio permiso. No es un error: se genera sin clima.
class UbicacionDenegada extends ResultadoUbicacion {
  const UbicacionDenegada();
}

/// No hay ubicacion: el target no la soporta, se agoto el tiempo o la posicion
/// no se pudo determinar.
class UbicacionNoDisponible extends ResultadoUbicacion {
  const UbicacionNoDisponible();
}

abstract interface class ServicioUbicacion {
  /// Si este target sabe pedir la ubicacion. En falso, ni se ofrece.
  bool get disponible;

  /// Pide la posicion. La primera vez el navegador pregunta al usuario.
  Future<ResultadoUbicacion> obtener();
}
