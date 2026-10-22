/// La ubicacion fuera de web: todavia no existe.
///
/// En Android hara falta un plugin con su permiso en el manifiesto. Hasta
/// entonces la app no la ofrece y genera sin clima, que el motor ya soporta.
library;

import 'contratos.dart';

class _SinUbicacion implements ServicioUbicacion {
  const _SinUbicacion();

  @override
  bool get disponible => false;

  @override
  Future<ResultadoUbicacion> obtener() =>
      Future<ResultadoUbicacion>.value(const UbicacionNoDisponible());
}

ServicioUbicacion crearServicioUbicacion() => const _SinUbicacion();
