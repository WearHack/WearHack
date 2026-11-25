/// La remocion de fondo con LiteRT (issue #12). Solo movil: depende de
/// `dart:ffi` a traves de `tflite_flutter`, y lo importa unicamente
/// `captura_movil.dart`.
library;

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:wearhack/core/clasificacion/pipeline_prendas.dart';
import 'package:wearhack/core/clasificacion/removedor_fondo.dart';
import 'package:wearhack/platform/captura/modelo_litert.dart';

/// u2netp en FP16, desde los assets (ver `assets/models/README.md`).
///
/// Como [ClasificadorLiteRT]: cada [quitarFondo] carga el interprete, lo usa y
/// lo cierra en un isolate aparte, asi que nunca esta en memoria a la vez que
/// el clasificador. El decodificado del JPEG y la mascara corren en ese isolate.
class RemovedorDeFondoLiteRT implements RemovedorDeFondo {
  RemovedorDeFondoLiteRT({this.asset = 'assets/models/u2netp.tflite'});

  final String asset;

  @override
  Future<img.Image> quitarFondo(Uint8List foto) => conArchivoLiteRT(
    asset,
    (String ruta) => Isolate.run(
      () => quitarFondoConMascara(foto, (Float32List e) => _inferir(ruta, e)),
    ),
  );
}

Float32List _inferir(String ruta, Float32List entrada) {
  final InterpreterOptions opciones = InterpreterOptions()..threads = 2;
  Interpreter? interprete;
  try {
    interprete = Interpreter.fromFile(File(ruta), options: opciones);
    final Tensor tensorEntrada = interprete.getInputTensor(0);
    final List<int> forma = tensorEntrada.shape;
    if (forma.length != 4 ||
        forma[0] != 1 ||
        forma[1] != ladoEntradaRemovedor ||
        forma[2] != ladoEntradaRemovedor ||
        forma[3] != 3 ||
        tensorEntrada.type != TensorType.float32) {
      throw FormatException(
        'u2netp espera $forma ${tensorEntrada.type}; '
        'se esperaba [1, 320, 320, 3] float32',
      );
    }
    final Tensor salida = interprete.getOutputTensor(0);
    final List<int> formaSalida = salida.shape;
    if (formaSalida.length != 4 ||
        formaSalida[0] != 1 ||
        formaSalida[1] != ladoEntradaRemovedor ||
        formaSalida[2] != ladoEntradaRemovedor ||
        formaSalida[3] != 1 ||
        salida.type != TensorType.float32) {
      throw const FormatException('La máscara de u2netp no es compatible');
    }
    tensorEntrada.data = entrada.buffer.asUint8List();
    interprete.invoke();
    // Copia: la vista apunta a memoria del interprete, que se cierra abajo.
    return Float32List.fromList(Float32List.sublistView(salida.data));
  } finally {
    interprete?.close();
    opciones.delete();
  }
}
