import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:wearhack/core/clasificacion/pipeline_prendas.dart';
import 'package:wearhack/platform/captura/modelo_litert.dart';

/// Ejecuta U²-Net en un isolate y libera el intérprete antes de clasificar.
class RemovedorLiteRT implements RemovedorDeFondo {
  @override
  Future<img.Image> quitarFondo(Uint8List foto) => conArchivoLiteRT(
    'assets/models/u2netp.tflite',
    (String ruta) => Isolate.run(() => _segmentar(ruta, foto)),
  );
}

const int _ladoModelo = 320;
const int _ladoMaximo = 768;

img.Image _segmentar(String ruta, Uint8List foto) {
  final img.Image? decodificada = img.decodeJpg(foto);
  if (decodificada == null) {
    throw const FormatException('No se pudo leer el JPEG de la prenda');
  }
  final img.Image vertical = img.bakeOrientation(decodificada);
  final int lado = math.max(vertical.width, vertical.height);
  final img.Image imagen = lado <= _ladoMaximo
      ? vertical
      : img.copyResize(
          vertical,
          width: math.max(1, (vertical.width * _ladoMaximo / lado).round()),
          height: math.max(1, (vertical.height * _ladoMaximo / lado).round()),
          interpolation: img.Interpolation.average,
        );
  final img.Image reducida = img.copyResize(
    imagen,
    width: _ladoModelo,
    height: _ladoModelo,
    interpolation: img.Interpolation.linear,
  );
  final Uint8List rgb = reducida.getBytes(order: img.ChannelOrder.rgb);
  // Esta exportación incluye la normalización y recibe RGB en [0, 255].
  final Float32List entrada = Float32List(rgb.length);
  for (int i = 0; i < rgb.length; i++) {
    entrada[i] = rgb[i].toDouble();
  }
  final Float32List probabilidades = _inferir(ruta, entrada);
  return aplicarMascaraPrenda(imagen, probabilidades);
}

Float32List _inferir(String ruta, Float32List entrada) {
  final InterpreterOptions opciones = InterpreterOptions()..threads = 2;
  try {
    final Interpreter interprete = Interpreter.fromFile(
      File(ruta),
      options: opciones,
    );
    try {
      final Tensor tensorEntrada = interprete.getInputTensor(0);
      final Tensor tensorSalida = interprete.getOutputTensor(0);
      if (!_valido(tensorEntrada, 3) || !_valido(tensorSalida, 1)) {
        throw const FormatException('Tensores de U²-Net incompatibles');
      }
      tensorEntrada.data = entrada.buffer.asUint8List();
      interprete.invoke();
      return Float32List.fromList(Float32List.sublistView(tensorSalida.data));
    } finally {
      interprete.close();
    }
  } finally {
    opciones.delete();
  }
}

bool _valido(Tensor tensor, int canales) {
  final List<int> forma = tensor.shape;
  return tensor.type == TensorType.float32 &&
      forma.length == 4 &&
      forma[0] == 1 &&
      forma[1] == _ladoModelo &&
      forma[2] == _ladoModelo &&
      forma[3] == canales;
}

/// Descarta máscaras que solo conservan un fragmento del encuadre y recorta
/// el espacio transparente antes de enviar la prenda al clasificador.
img.Image aplicarMascaraPrenda(img.Image imagen, Float32List probabilidades) {
  double minimo = double.infinity;
  double maximo = double.negativeInfinity;
  for (final double valor in probabilidades) {
    if (!valor.isFinite) throw const PrendaSinPixeles();
    minimo = math.min(valor, minimo);
    maximo = math.max(valor, maximo);
  }
  if (maximo - minimo < 1e-6) throw const PrendaSinPixeles();

  final img.Image mascara = img.Image(
    width: _ladoModelo,
    height: _ladoModelo,
    numChannels: 1,
  );
  for (final img.Pixel pixel in mascara) {
    final double valor = probabilidades[pixel.y * _ladoModelo + pixel.x];
    pixel.r = ((valor - minimo) / (maximo - minimo) * 255).round();
  }
  final img.Image ampliada = img.copyResize(
    mascara,
    width: imagen.width,
    height: imagen.height,
    interpolation: img.Interpolation.linear,
  );
  final img.Image salida = img.Image(
    width: imagen.width,
    height: imagen.height,
    numChannels: 4,
  );
  int primerX = imagen.width;
  int primerY = imagen.height;
  int ultimoX = -1;
  int ultimoY = -1;
  int pixelesPrenda = 0;
  for (final img.Pixel pixel in ampliada) {
    if (pixel.r < 128) {
      // Conserva RGBA ceros también bajo la transparencia.
      continue;
    }
    pixelesPrenda++;
    primerX = math.min(primerX, pixel.x);
    primerY = math.min(primerY, pixel.y);
    ultimoX = math.max(ultimoX, pixel.x);
    ultimoY = math.max(ultimoY, pixel.y);
    final img.Pixel origen = imagen.getPixel(pixel.x, pixel.y);
    salida.setPixelRgba(pixel.x, pixel.y, origen.r, origen.g, origen.b, 255);
  }
  final int area = imagen.width * imagen.height;
  if (pixelesPrenda == area || pixelesPrenda < area * 0.05) {
    throw const EncuadrePrendaInsuficiente();
  }
  return img.copyCrop(
    salida,
    x: primerX,
    y: primerY,
    width: ultimoX - primerX + 1,
    height: ultimoY - primerY + 1,
  );
}

class EncuadrePrendaInsuficiente implements Exception {
  const EncuadrePrendaInsuficiente();

  @override
  String toString() =>
      'No se distinguió la prenda del fondo. Centra la prenda completa '
      'y usa un fondo liso que contraste.';
}
