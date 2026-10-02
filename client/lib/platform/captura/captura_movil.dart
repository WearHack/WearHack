/// Implementacion para Android e iOS. Stub.
///
/// Este archivo solo entra en la build cuando existe `dart:io`, es decir en
/// movil. La build de web no lo compila nunca, asi que aqui se puede depender
/// de LiteRT y de ML Kit sin romper el target web.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wearhack/core/recorte/configuracion_recorte.dart';
import 'package:wearhack/core/recorte/recortador_facial.dart';
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

/// Detector de rostros con ML Kit.
///
/// ML Kit entra con `com.google.mlkit:face-detection`, la variante con el modelo
/// incluido en la app: no descarga nada en tiempo de ejecucion, asi que no hay
/// trafico de red.
///
/// El plugin solo acepta una ruta de archivo para una imagen codificada, asi
/// que la copia reducida y vertical se escribe en el directorio temporal
/// privado de la app y se borra en un `finally`, pase lo que pase.
///
/// TODO(ia): crea y cierra un detector por llamada. Para 270 fotos de
/// calibracion sobra; si el flujo real lo necesita mas rapido, reutilizarlo.
class DetectorRostroMlKit implements DetectorRostro {
  @override
  Future<List<CajaRostro>> detectar(Uint8List jpegVertical) async {
    final Directory directorio = await getTemporaryDirectory();
    final File archivo = File(
      '${directorio.path}/deteccion_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    final FaceDetector detector = FaceDetector(
      options: FaceDetectorOptions(performanceMode: FaceDetectorMode.accurate),
    );
    try {
      await archivo.writeAsBytes(jpegVertical, flush: true);
      final List<Face> rostros = await detector.processImage(
        InputImage.fromFilePath(archivo.path),
      );
      return <CajaRostro>[
        for (final Face rostro in rostros)
          CajaRostro(
            left: rostro.boundingBox.left,
            top: rostro.boundingBox.top,
            width: rostro.boundingBox.width,
            height: rostro.boundingBox.height,
          ),
      ];
    } finally {
      await detector.close();
      if (await archivo.exists()) await archivo.delete();
    }
  }
}

Future<R> _enUnIsolateAparte<R>(FutureOr<R> Function() tarea) =>
    Isolate.run(tarea);

/// Recorte de rostro del telefono: ML Kit detecta y [RecortadorFacial] hace el
/// resto, en un isolate aparte para no congelar la interfaz.
///
/// Los parametros del constructor existen para las pruebas. En la app se usa
/// `crearFaceCropper()`, que lee los margenes de los `--dart-define`.
class FaceCropperMovil implements FaceCropper {
  FaceCropperMovil({this._detector, this._configuracion, this._ejecutor});

  final DetectorRostro? _detector;
  final ConfiguracionRecorte? _configuracion;
  final Ejecutor? _ejecutor;

  @override
  bool get disponible => true;

  @override
  Future<RecorteFacial?> recortar(Uint8List foto) async {
    // La configuracion se lee primero: sin margenes no hay recorte, y se dice
    // antes de gastar tiempo en decodificar nada.
    final ConfiguracionRecorte configuracion =
        _configuracion ?? ConfiguracionRecorte.desdeEntorno();
    return await RecortadorFacial(
      detector: _detector ?? DetectorRostroMlKit(),
      configuracion: configuracion,
      ejecutor: _ejecutor ?? _enUnIsolateAparte,
    ).recortar(foto);
  }
}

GarmentPipeline crearGarmentPipeline() => GarmentPipelineMovil();

FaceCropper crearFaceCropper() => FaceCropperMovil();
