/// El clasificador de prendas con LiteRT (issue #13). Solo movil: depende de
/// `dart:ffi` a traves de `tflite_flutter`, y lo importa unicamente
/// `captura_movil.dart`.
library;

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:wearhack/core/clasificacion/clasificador_prenda.dart';
import 'package:wearhack/platform/captura/modelo_litert.dart';

/// `prendas-v1` en FP16, desde los assets (ver `assets/models/README.md`).
///
/// Cada [clasificar] carga el interprete, lo usa y lo cierra, en un isolate
/// aparte: la inferencia no congela la interfaz y el modelo no queda en memoria
/// cuando le toca a u2netp.
///
/// En CPU con dos hilos. El delegado de GPU queda para cuando se mida en el
/// telefono de referencia: en un MobileNetV3-Small no siempre compensa.
class ClasificadorLiteRT implements ClasificadorDePrendas {
  ClasificadorLiteRT({this.asset = 'assets/models/clasificador_prenda.tflite'});

  final String asset;

  @override
  Future<Clasificacion> clasificar(img.Image prendaSinFondo) async {
    final Float32List entrada = entradaDelClasificador(prendaSinFondo);
    final List<List<double>> salidas = await conArchivoLiteRT(
      asset,
      (String ruta) => Isolate.run(() => _inferir(ruta, entrada)),
    );
    return leerSalidasDelClasificador(salidas);
  }
}

List<List<double>> _inferir(String ruta, Float32List entrada) {
  final InterpreterOptions opciones = InterpreterOptions()..threads = 2;
  final Interpreter interprete = Interpreter.fromFile(
    File(ruta),
    options: opciones,
  );
  try {
    final Tensor tensorEntrada = interprete.getInputTensor(0);
    final List<int> forma = tensorEntrada.shape;
    if (forma.length != 4 ||
        forma[1] != ladoEntradaClasificador ||
        forma[2] != ladoEntradaClasificador ||
        forma[3] != 3 ||
        tensorEntrada.type != TensorType.float32) {
      throw FormatException(
        'El clasificador espera $forma ${tensorEntrada.type}; '
        'se esperaba [1, 224, 224, 3] float32',
      );
    }
    tensorEntrada.data = entrada.buffer.asUint8List();
    interprete.invoke();
    return <List<double>>[
      for (final Tensor salida in interprete.getOutputTensors())
        // Copia: la vista apunta a memoria del interprete, que se cierra abajo.
        List<double>.of(Float32List.sublistView(salida.data)),
    ];
  } finally {
    interprete.close();
    opciones.delete();
  }
}
