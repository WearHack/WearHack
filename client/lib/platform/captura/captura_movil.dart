/// Implementacion para Android e iOS. Stub.
///
/// Este archivo solo entra en la build cuando existe `dart:io`, es decir en
/// movil. La build de web no lo compila nunca, asi que aqui se puede depender
/// de LiteRT y de ML Kit sin romper el target web.
library;

import 'dart:typed_data';

import 'package:wearhack/platform/captura/contratos.dart';

/// Pipeline on-device con LiteRT/TFLite.
///
/// Pendiente de implementar. Cuando se haga:
///
/// 1. Cargar `u2netp.tflite`, quitar el fondo, **liberar el interprete**.
/// 2. Cargar `clasificador_prenda.tflite`, sacar tipo, textura y patron de sus
///    tres cabezas, **liberar el interprete**.
/// 3. Calcular el color base sobre los pixeles no transparentes y pasarlo a Lab.
///
/// Los pasos 1 y 2 no se solapan: es lo que permite que esto corra en gama
/// media-baja.
class GarmentPipelineMovil implements GarmentPipeline {
  @override
  bool get disponible => true;

  @override
  Future<void> preparar() async {
    // TODO(ia): comprobar que los modelos estan en assets/models/ y elegir
    // delegado (NNAPI o Core ML) con reserva a CPU.
    throw UnimplementedError('GarmentPipelineMovil.preparar');
  }

  @override
  Future<PrendaClasificada> procesar(Uint8List foto) async {
    // TODO(ia): los tres pasos de arriba, uno detras de otro.
    throw UnimplementedError('GarmentPipelineMovil.procesar');
  }

  @override
  Future<void> liberar() async {
    // TODO(ia): cerrar cualquier interprete que siguiera abierto.
    throw UnimplementedError('GarmentPipelineMovil.liberar');
  }
}

/// Recorte de rostro con ML Kit. Stub.
///
/// ML Kit trae su propio modelo dentro del paquete, asi que no hay nada que
/// poner en assets/models/ para esto.
class FaceCropperMovil implements FaceCropper {
  @override
  bool get disponible => true;

  @override
  Future<Uint8List?> recortar(Uint8List foto) async {
    // TODO(ia): detectar con ML Kit, quedarse con la cara mas grande, alinear
    // por los ojos, recortar con margen y normalizar tamano e iluminacion.
    throw UnimplementedError('FaceCropperMovil.recortar');
  }
}

GarmentPipeline crearGarmentPipeline() => GarmentPipelineMovil();

FaceCropper crearFaceCropper() => FaceCropperMovil();
