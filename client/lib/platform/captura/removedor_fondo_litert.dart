/// La remocion de fondo con LiteRT (issue #12). Solo movil: depende de
/// `dart:ffi` a traves de `tflite_flutter`, y lo importa unicamente
/// `captura_movil.dart`.
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:wearhack/core/clasificacion/pipeline_prendas.dart';
import 'package:wearhack/core/clasificacion/removedor_fondo.dart';

/// u2netp en FP16, desde los assets (ver `assets/models/README.md`).
///
/// Como [ClasificadorLiteRT]: cada [quitarFondo] carga el interprete, lo usa y
/// lo cierra en un isolate aparte, asi que nunca esta en memoria a la vez que
/// el clasificador. Se guardan solo los bytes del archivo (2,5 MB). El
/// decodificado del JPEG y la mascara tambien corren en ese isolate.
class RemovedorDeFondoLiteRT implements RemovedorDeFondo {
  RemovedorDeFondoLiteRT({this.asset = 'assets/models/u2netp.tflite'});

  final String asset;
  Uint8List? _modelo;

  @override
  Future<img.Image> quitarFondo(Uint8List foto) async {
    final Uint8List modelo = _modelo ??= (await rootBundle.load(asset)).buffer
        .asUint8List();
    return Isolate.run(
      () => quitarFondoConMascara(foto, (Float32List e) => _inferir(modelo, e)),
    );
  }
}

Float32List _inferir(Uint8List modelo, Float32List entrada) {
  final InterpreterOptions opciones = InterpreterOptions()..threads = 2;
  final Interpreter interprete = Interpreter.fromBuffer(
    modelo,
    options: opciones,
  );
  try {
    final Tensor tensorEntrada = interprete.getInputTensor(0);
    final List<int> forma = tensorEntrada.shape;
    if (forma.length != 4 ||
        forma[1] != ladoEntradaRemovedor ||
        forma[2] != ladoEntradaRemovedor ||
        forma[3] != 3 ||
        tensorEntrada.type != TensorType.float32) {
      throw FormatException(
        'u2netp espera $forma ${tensorEntrada.type}; '
        'se esperaba [1, 320, 320, 3] float32',
      );
    }
    tensorEntrada.data = entrada.buffer.asUint8List();
    interprete.invoke();
    // Copia: la vista apunta a memoria del interprete, que se cierra abajo.
    return Float32List.fromList(
      Float32List.sublistView(interprete.getOutputTensor(0).data),
    );
  } finally {
    interprete.close();
    opciones.delete();
  }
}
