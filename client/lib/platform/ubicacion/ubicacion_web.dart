/// La ubicacion en web, con la Geolocation API del navegador.
///
/// Usa `dart:js_interop` directamente en vez de un plugin: son tres llamadas y
/// no justifican una dependencia. Este archivo solo compila en web; el resto de
/// la app lo alcanza a traves de `platform/ubicacion.dart`.
library;

import 'dart:async';
import 'dart:js_interop';

import 'contratos.dart';

@JS('navigator.geolocation')
external _Geolocalizacion? get _geolocalizacion;

extension type _Geolocalizacion._(JSObject _) implements JSObject {
  external void getCurrentPosition(
    JSFunction exito,
    JSFunction error,
    _Opciones opciones,
  );
}

extension type _Posicion._(JSObject _) implements JSObject {
  external _Coordenadas get coords;
}

extension type _Coordenadas._(JSObject _) implements JSObject {
  external double get latitude;
  external double get longitude;
}

extension type _ErrorDePosicion._(JSObject _) implements JSObject {
  /// 1 es PERMISSION_DENIED; 2 y 3 son posicion no disponible y tiempo agotado.
  external int get code;
}

extension type _Opciones._(JSObject _) implements JSObject {
  external factory _Opciones({
    bool enableHighAccuracy,
    int timeout,
    int maximumAge,
  });
}

class _UbicacionNavegador implements ServicioUbicacion {
  const _UbicacionNavegador();

  static const int _permisoDenegado = 1;

  @override
  bool get disponible => _geolocalizacion != null;

  @override
  Future<ResultadoUbicacion> obtener() {
    final _Geolocalizacion? geo = _geolocalizacion;
    if (geo == null) {
      return Future<ResultadoUbicacion>.value(const UbicacionNoDisponible());
    }

    final Completer<ResultadoUbicacion> resultado =
        Completer<ResultadoUbicacion>();
    geo.getCurrentPosition(
      ((_Posicion p) {
        resultado.complete(
          UbicacionObtenida(
            latitud: p.coords.latitude,
            longitud: p.coords.longitude,
          ),
        );
      }).toJS,
      ((_ErrorDePosicion e) {
        resultado.complete(
          e.code == _permisoDenegado
              ? const UbicacionDenegada()
              : const UbicacionNoDisponible(),
        );
      }).toJS,
      // Para el clima basta la ciudad: sin alta precision (no enciende el GPS)
      // y vale una posicion de hace media hora.
      _Opciones(
        enableHighAccuracy: false,
        timeout: 10000,
        maximumAge: 30 * 60 * 1000,
      ),
    );
    return resultado.future;
  }
}

ServicioUbicacion crearServicioUbicacion() => const _UbicacionNavegador();
