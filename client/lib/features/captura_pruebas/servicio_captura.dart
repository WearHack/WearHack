/// Registra una toma: llama al recorte real del producto y guarda el resultado.
///
/// La regla 5 de la spec ("mismo recorte que el producto") queda garantizada por
/// construccion: este servicio **no** recibe un recorte hecho por otro, recibe
/// el [FaceCropper] y lo llama el mismo. No hay una segunda ruta de recorte.
library;

import 'dart:typed_data';

import 'package:wearhack/core/recorte/controles_calidad.dart';
import 'package:wearhack/features/captura_pruebas/almacen_capturas.dart';
import 'package:wearhack/features/captura_pruebas/metadatos.dart';
import 'package:wearhack/features/captura_pruebas/modelos.dart';
import 'package:wearhack/features/captura_pruebas/parametros_exif.dart';
import 'package:wearhack/platform/captura/contratos.dart';

/// No hay una autorizacion de calibracion firmada para esta persona.
class AutorizacionNoConfirmada implements Exception {
  const AutorizacionNoConfirmada(this.seudonimo);

  final Seudonimo seudonimo;

  @override
  String toString() =>
      'AutorizacionNoConfirmada: falta confirmar la autorizacion de '
      'calibracion firmada de $seudonimo';
}

/// El recorte no encontro un rostro usable. La foto no se guarda.
class SinRostro implements Exception {
  const SinRostro();

  @override
  String toString() => 'SinRostro: no se vio un rostro usable; repite la toma';
}

/// Lo que devuelve [ServicioCapturaPruebas.registrarToma]: los metadatos que se
/// guardaron y los controles de calidad del recorte.
///
/// Los controles no van en el JSON (se pueden recalcular), pero la pantalla los
/// necesita para sugerir repetir la toma con una recomendacion concreta.
class ResultadoRegistro {
  const ResultadoRegistro({required this.metadatos, required this.controles});

  final MetadatosToma metadatos;
  final ControlesCalidad controles;
}

class ServicioCapturaPruebas {
  const ServicioCapturaPruebas({required this.almacen, required this.cropper});

  final AlmacenCapturas almacen;
  final FaceCropper cropper;

  /// Recorta y guarda la toma.
  ///
  /// [autorizacionFirmada] es la casilla "Autorizacion de calibracion firmada"
  /// de la persona. Se exige aqui y no solo en la pantalla: sin ella no se
  /// toca ni el recorte ni el disco.
  ///
  /// Lanza [AutorizacionNoConfirmada], [SinRostro] (sin escribir nada),
  /// [TomaYaExiste], y lo que lance el recorte (`ConfiguracionRecorteInvalida`,
  /// `PerfilIccNoSoportado`, `FormatException`).
  Future<ResultadoRegistro> registrarToma({
    required IdToma id,
    required bool autorizacionFirmada,
    required Uint8List foto,
    required DatosDelCelular celular,
    required DateTime momento,
    ParametrosDeCamara? parametrosCamara,
    String extensionFoto = 'jpg',
    bool reemplazar = false,
  }) async {
    if (!autorizacionFirmada) throw AutorizacionNoConfirmada(id.seudonimo);

    final RecorteFacial? recorte = await cropper.recortar(foto);
    if (recorte == null) throw const SinRostro();

    final MetadatosToma metadatos = await almacen.guardarToma(
      id: id,
      foto: foto,
      extensionFoto: extensionFoto,
      recorte: recorte,
      celular: celular,
      parametrosCamara: parametrosCamara ?? leerParametrosDeCamara(foto),
      momento: momento,
      reemplazar: reemplazar,
    );
    return ResultadoRegistro(
      metadatos: metadatos,
      controles: recorte.controles,
    );
  }
}
