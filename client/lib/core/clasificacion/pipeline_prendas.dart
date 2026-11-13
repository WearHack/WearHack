/// El pipeline on-device de una prenda (issues #12 y #13), sin plugins: quitar
/// el fondo, clasificar y sacar el color base.
///
/// Los modelos llegan inyectados, y la rama movil les pone LiteRT. Asi el orden
/// de los pasos, la carga de un modelo a la vez y lo que sale se prueban sin
/// telefono.
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:wearhack/core/clasificacion/clasificador_prenda.dart';
import 'package:wearhack/core/color/categoria_color.dart';
import 'package:wearhack/core/color/color_base.dart';
import 'package:wearhack/platform/captura/contratos.dart';

/// Quita el fondo de la foto de una prenda (u2netp, issue #12).
abstract interface class RemovedorDeFondo {
  /// Recibe el JPEG de la camara y devuelve la prenda en RGBA, con el fondo
  /// transparente.
  Future<img.Image> quitarFondo(Uint8List foto);
}

/// Mientras no este u2netp (#12).
///
/// Falla a proposito en vez de dejar pasar la foto entera: la foto original no
/// sale del telefono, y sin fondo quitado lo unico que podria subirse es ella.
/// La cola reintenta y, agotados los intentos, la conserva como fallida.
class RemovedorDeFondoPendiente implements RemovedorDeFondo {
  const RemovedorDeFondoPendiente();

  @override
  Future<img.Image> quitarFondo(Uint8List foto) async =>
      throw const CapturaNoDisponible(
        'falta el modelo de remocion de fondo (u2netp, issue #12)',
      );
}

/// La prenda no tiene pixeles opacos despues de quitar el fondo: u2netp no
/// encontro nada que recortar.
class PrendaSinPixeles implements Exception {
  const PrendaSinPixeles();

  @override
  String toString() =>
      'PrendaSinPixeles: no quedo nada de la prenda al quitar el fondo';
}

/// Los tres pasos, uno detras de otro. Cada modelo se carga, se usa y se suelta
/// dentro de su paso, asi que nunca hay dos en memoria a la vez.
class PipelinePrendasOnDevice implements GarmentPipeline {
  PipelinePrendasOnDevice({
    required this._removedor,
    required this._clasificador,
    required ConfiguracionColorBase Function() configuracionColor,
  }) : _leerConfiguracionColor = configuracionColor;

  final RemovedorDeFondo _removedor;
  final ClasificadorDePrendas _clasificador;
  final ConfiguracionColorBase Function() _leerConfiguracionColor;
  ConfiguracionColorBase? _configuracionColor;

  @override
  bool get disponible => true;

  /// Lee la configuracion del color base. Si falta, el lote entero falla aqui,
  /// antes de gastar tiempo en quitar fondos.
  @override
  Future<void> preparar() async {
    _configuracionColor ??= _leerConfiguracionColor();
  }

  @override
  Future<PrendaClasificada> procesar(Uint8List foto) async {
    final ConfiguracionColorBase configuracion = _configuracionColor ??=
        _leerConfiguracionColor();

    final img.Image prenda = await _removedor.quitarFondo(foto);
    final Clasificacion clasificacion = await _clasificador.clasificar(prenda);

    final img.Image rgba = prenda.numChannels == 4
        ? prenda
        : prenda.convert(numChannels: 4);
    final ResultadoColorBase? color = calcularColorBase(
      rgba: rgba.getBytes(order: img.ChannelOrder.rgba),
      ancho: rgba.width,
      alto: rgba.height,
      configuracion: configuracion,
    );
    if (color == null) throw const PrendaSinPixeles();

    return PrendaClasificada(
      imagenSinFondo: img.encodePng(rgba),
      tipo: clasificacion.tipo,
      confianzaTipo: clasificacion.confianzaTipo,
      patron: clasificacion.patron,
      confianzaPatron: clasificacion.confianzaPatron,
      color: color.color,
      categoriaColor: categoriaDeLab(color.color),
    );
  }

  /// Los modelos se sueltan en cada paso; aqui no queda nada abierto.
  @override
  Future<void> liberar() async {}
}
