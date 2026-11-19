/// Implementacion para Android e iOS.
///
/// Este archivo solo entra en la build cuando existe `dart:io`, es decir en
/// movil. La build de web no lo compila nunca, asi que aqui se puede depender
/// de LiteRT y de ML Kit sin romper el target web.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:thermal/thermal.dart';
import 'package:wearhack/core/clasificacion/pipeline_prendas.dart';
import 'package:wearhack/core/color/categoria_color.dart';
import 'package:wearhack/core/color/color_base.dart';
import 'package:wearhack/core/recorte/configuracion_recorte.dart';
import 'package:wearhack/core/recorte/recortador_facial.dart';
import 'package:wearhack/features/closet/captura/captura_de_prendas.dart';
import 'package:wearhack/features/closet/captura/cola_captura.dart';
import 'package:wearhack/features/closet/captura/estado_termico.dart';
import 'package:wearhack/features/closet/captura/subidor_pendiente.dart';
import 'package:wearhack/platform/captura/almacen_cola_archivos.dart';
import 'package:wearhack/platform/captura/camara.dart';
import 'package:wearhack/platform/captura/clasificador_litert.dart';
import 'package:wearhack/platform/captura/contratos.dart';

/// Pipeline on-device de prendas: fondo, clasificacion y color base, con un
/// modelo en memoria a la vez (ver [PipelinePrendasOnDevice]).
///
/// La remocion de fondo es [RemovedorDeFondoPendiente] hasta que este u2netp
/// (#12): sin ella el pipeline falla en vez de subir la foto original.
GarmentPipeline crearGarmentPipeline() => PipelinePrendasOnDevice(
  removedor: const RemovedorDeFondoPendiente(),
  clasificador: ClasificadorLiteRT(),
  configuracionColor: ConfiguracionColorBase.desdeEntorno,
  tablaColores: () async =>
      TablaIsccNbs.desdeJson(await rootBundle.loadString(assetTablaIsccNbs)),
);

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

FaceCropper crearFaceCropper() => FaceCropperMovil();

// ---------------------------------------------------------------------------
// Captura de prendas en cola (issue #11)
// ---------------------------------------------------------------------------

/// La camara trasera, para fotografiar prendas.
CamaraDeCaptura crearCamaraTrasera() => CamaraTrasera();

/// La camara trasera con el plugin `camera`.
///
/// Sin guia de distancia: esa mide un rostro, y aqui no lo hay. Como la
/// frontal, lee la foto a bytes y borra en un `finally` el archivo temporal que
/// deja el plugin, para que la foto solo exista en el almacen de la cola.
class CamaraTrasera implements CamaraDeCaptura {
  CameraController? _controlador;

  @override
  bool get guiaDeDistanciaActiva => false;

  @override
  Stream<int?> get anchoDelRostroEnVivo => const Stream<int?>.empty();

  @override
  Future<void> inicializar() async {
    final List<CameraDescription> camaras = await availableCameras();
    final CameraDescription? trasera = camaras
        .where(
          (CameraDescription c) => c.lensDirection == CameraLensDirection.back,
        )
        .firstOrNull;
    if (trasera == null) throw const SinCamaraTrasera();
    // `high` y no `max`: la prenda se reduce para u2netp y el clasificador, y
    // una foto de 12 MP solo hace mas lento cada disparo y cada lote.
    final CameraController c = CameraController(
      trasera,
      ResolutionPreset.high,
      enableAudio: false,
    );
    _controlador = c;
    await c.initialize();
    await c.setFlashMode(FlashMode.off);
  }

  @override
  Widget vistaPrevia() => CameraPreview(_controlador!);

  @override
  Future<FotoTomada> tomarFoto() async {
    final XFile archivo = await _controlador!.takePicture();
    try {
      final String ext = p
          .extension(archivo.path)
          .replaceFirst('.', '')
          .toLowerCase();
      if (ext != 'jpg' && ext != 'jpeg') {
        throw StateError(
          'La camara entrego un formato inesperado: .$ext (se esperaba JPEG)',
        );
      }
      return FotoTomada(bytes: await archivo.readAsBytes(), extension: 'jpg');
    } finally {
      try {
        await File(archivo.path).delete();
      } on FileSystemException {
        // Ya no estaba.
      }
    }
  }

  @override
  Future<void> liberar() async {
    final CameraController? c = _controlador;
    _controlador = null;
    await c?.dispose();
  }
}

/// El estado termico del telefono con el plugin `thermal`.
EstadoTermicoDispositivo crearEstadoTermico() {
  final Thermal thermal = Thermal();
  return EstadoTermicoDispositivo(
    // Los dos enums tienen los mismos niveles en el mismo orden.
    niveles: thermal.onThermalStatusChanged.map(
      (ThermalStatus s) => NivelTermico.values[s.index],
    ),
    temperaturasBateria: thermal.onBatteryTemperatureChanged,
    umbral: UmbralTermico.desdeEntorno(),
  );
}

/// Abre la captura de prendas con lo que tiene el telefono: el almacen privado
/// de la app, el pipeline on-device, el sensor termico y la camara trasera.
///
/// El subidor es [SubidorPendiente] hasta que el Closet reciba prendas (#25):
/// las procesadas esperan en la cola sin perderse.
Future<CapturaDePrendas> abrirCapturaDePrendas() async {
  final EstadoTermico termico = crearEstadoTermico();
  final ColaCaptura cola = await ColaCaptura.abrir(
    almacen: await AlmacenColaArchivos.enSoporteDeLaApp(),
    procesador: ProcesadorSobrePipeline(crearGarmentPipeline()),
    subidor: const SubidorPendiente(),
    termico: termico,
  );
  return CapturaDePrendas(
    cola: cola,
    termico: termico,
    crearCamara: crearCamaraTrasera,
  );
}
