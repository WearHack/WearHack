/// El modo de captura de pruebas en Android e iOS: las piezas que tocan la
/// plataforma (camara, informacion del dispositivo, hoja de compartir) y el
/// punto de entrada que las junta.
///
/// Solo entra en la build cuando existe `dart:io`, es decir en movil: la rama de
/// web usa `captura_pruebas_web.dart`. Las pantallas de
/// `features/captura_pruebas/ui/` no importan ningun plugin; reciben todo esto
/// por `DependenciasCaptura`.
///
/// **Nada de esto esta verificado en un telefono.** Compila y las pantallas se
/// prueban con piezas falsas, pero el plugin de camara, el permiso, la rotacion
/// de los fotogramas y la hoja de compartir solo se comprueban en un dispositivo.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wearhack/core/configuracion.dart';
import 'package:wearhack/features/captura_pruebas/almacen_capturas.dart';
import 'package:wearhack/features/captura_pruebas/servicio_captura.dart';
import 'package:wearhack/features/captura_pruebas/ui/camara.dart';
import 'package:wearhack/features/captura_pruebas/ui/dependencias.dart';
import 'package:wearhack/features/captura_pruebas/ui/pantalla_inicio.dart';
import 'package:wearhack/platform/captura.dart';

/// Abre el modo de captura de pruebas.
///
/// Solo se llama desde detras de `Configuracion.capturaPruebas`. Las fotos van
/// al directorio de documentos privado de la app: no es la galeria, y
/// `AlmacenCapturas` se niega a trabajar dentro de un repositorio.
Future<void> abrirCapturaPruebas(BuildContext context) async {
  final Directory documentos = await getApplicationDocumentsDirectory();
  final AlmacenCapturas almacen = AlmacenCapturas(
    Directory(p.join(documentos.path, 'captura_pruebas')),
  );
  final DependenciasCaptura dependencias = DependenciasCaptura(
    almacen: almacen,
    servicio: ServicioCapturaPruebas(
      almacen: almacen,
      // La MISMA funcion de recorte que usa el producto.
      cropper: crearFaceCropper(),
    ),
    crearCamara: CamaraFrontal.new,
    dispositivo: const LectorDeDispositivoReal(),
    compartir: _compartirZip,
  );
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PantallaInicioCaptura(dependencias: dependencias),
    ),
  );
}

Future<void> _compartirZip(File zip) async {
  await SharePlus.instance.share(
    ShareParams(
      files: <XFile>[XFile(zip.path)],
      subject: 'Lote de calibracion',
    ),
  );
}

/// Modelo, sistema y version de la app, leidos de la plataforma.
class LectorDeDispositivoReal implements LectorDeDispositivo {
  const LectorDeDispositivoReal();

  @override
  Future<InfoDelDispositivo> leer() async {
    final PackageInfo paquete = await PackageInfo.fromPlatform();
    final String build = '${paquete.version}+${paquete.buildNumber}';
    final DeviceInfoPlugin plugin = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final AndroidDeviceInfo a = await plugin.androidInfo;
      return InfoDelDispositivo(
        modelo: a.model.isEmpty ? 'sin dato' : a.model,
        sistema: 'Android ${a.version.release}',
        buildApp: build,
      );
    }
    if (Platform.isIOS) {
      final IosDeviceInfo i = await plugin.iosInfo;
      return InfoDelDispositivo(
        modelo: i.utsname.machine.isEmpty ? 'sin dato' : i.utsname.machine,
        sistema: '${i.systemName} ${i.systemVersion}',
        buildApp: build,
      );
    }
    throw UnsupportedError('Solo Android e iOS');
  }
}

/// La camara frontal con el plugin `camera`.
///
/// Resolucion maxima, flash apagado y sin audio. La foto se lee a bytes y el
/// archivo temporal que deja el plugin se borra en un `finally`: no queda
/// ninguna foto fuera del almacen privado.
class CamaraFrontal implements CamaraDeCaptura {
  CameraController? _controlador;
  FaceDetector? _detector;
  final StreamController<int?> _anchos = StreamController<int?>.broadcast();
  bool _pausada = false;
  bool _procesando = false;
  DateTime _ultimaDeteccion = DateTime.fromMillisecondsSinceEpoch(0);
  late CameraDescription _descripcion;

  static const Duration _entreDetecciones = Duration(milliseconds: 400);

  @override
  bool get guiaDeDistanciaActiva => Configuracion.capturaGuiaEnVivo;

  @override
  Stream<int?> get anchoDelRostroEnVivo => _anchos.stream;

  @override
  Future<void> inicializar() async {
    final List<CameraDescription> camaras = await availableCameras();
    final Iterable<CameraDescription> frontales = camaras.where(
      (CameraDescription c) => c.lensDirection == CameraLensDirection.front,
    );
    if (frontales.isEmpty) throw const SinCamaraFrontal();
    _descripcion = frontales.first;

    final CameraController c = CameraController(
      _descripcion,
      ResolutionPreset.max,
      enableAudio: false,
      // Solo afecta al stream de la guia: la foto sale siempre en JPEG.
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    _controlador = c;
    await c.initialize();
    await c.setFlashMode(FlashMode.off);

    if (guiaDeDistanciaActiva) {
      _detector = FaceDetector(
        options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast),
      );
      await _empezarDeteccion();
    }
  }

  @override
  Widget vistaPrevia() => CameraPreview(_controlador!);

  Future<void> _empezarDeteccion() async {
    final CameraController? c = _controlador;
    if (c == null || !c.value.isInitialized || c.value.isStreamingImages) {
      return;
    }
    await c.startImageStream(_alLlegarUnFotograma);
  }

  Future<void> _alLlegarUnFotograma(CameraImage imagen) async {
    final DateTime ahora = DateTime.now();
    if (_pausada ||
        _procesando ||
        ahora.difference(_ultimaDeteccion) < _entreDetecciones) {
      return;
    }
    _ultimaDeteccion = ahora;
    _procesando = true;
    try {
      final InputImage? entrada = _aInputImage(imagen);
      if (entrada == null) return;
      final List<Face> rostros = await _detector!.processImage(entrada);
      final int? ancho = rostros.isEmpty
          ? null
          : rostros
                .map((Face f) => f.boundingBox.width)
                .reduce(math.max)
                .round();
      if (!_anchos.isClosed) _anchos.add(ancho);
    } on Object {
      // Un fotograma que falla no apaga nada: se intenta con el siguiente.
    } finally {
      _procesando = false;
    }
  }

  static const Map<DeviceOrientation, int> _grados = <DeviceOrientation, int>{
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  /// Convierte un fotograma de la camara en la entrada de ML Kit. Es la receta
  /// del ejemplo oficial del plugin; **la rotacion no esta verificada en un
  /// telefono**.
  InputImage? _aInputImage(CameraImage imagen) {
    final CameraController c = _controlador!;
    final int sensor = _descripcion.sensorOrientation;
    InputImageRotation? rotacion;
    if (Platform.isIOS) {
      rotacion = InputImageRotationValue.fromRawValue(sensor);
    } else if (Platform.isAndroid) {
      int? compensacion = _grados[c.value.deviceOrientation];
      if (compensacion == null) return null;
      compensacion = (sensor + compensacion) % 360; // camara frontal
      rotacion = InputImageRotationValue.fromRawValue(compensacion);
    }
    if (rotacion == null) return null;

    final InputImageFormat? formato = InputImageFormatValue.fromRawValue(
      imagen.format.raw as int,
    );
    if (formato == null ||
        (Platform.isAndroid && formato != InputImageFormat.nv21) ||
        (Platform.isIOS && formato != InputImageFormat.bgra8888)) {
      return null;
    }
    if (imagen.planes.length != 1) return null;
    final Plane plano = imagen.planes.first;
    return InputImage.fromBytes(
      bytes: plano.bytes,
      metadata: InputImageMetadata(
        size: Size(imagen.width.toDouble(), imagen.height.toDouble()),
        rotation: rotacion,
        format: formato,
        bytesPerRow: plano.bytesPerRow,
      ),
    );
  }

  @override
  Future<FotoTomada> tomarFoto() async {
    final CameraController c = _controlador!;
    _pausada = true;
    try {
      // Tomar la foto con el stream encendido falla en algunos equipos.
      if (c.value.isStreamingImages) await c.stopImageStream();
      final XFile archivo = await c.takePicture();
      try {
        final String ext = p
            .extension(archivo.path)
            .replaceFirst('.', '')
            .toLowerCase();
        final String extension = switch (ext) {
          'jpg' || 'jpeg' => 'jpg',
          'heic' || 'heif' => 'heic',
          _ => throw StateError(
            'La camara entrego un formato inesperado: .$ext',
          ),
        };
        return FotoTomada(
          bytes: await archivo.readAsBytes(),
          extension: extension,
        );
      } finally {
        // La foto solo debe existir en el almacen privado.
        try {
          await File(archivo.path).delete();
        } on FileSystemException {
          // Ya no estaba.
        }
      }
    } finally {
      _pausada = false;
      if (guiaDeDistanciaActiva) {
        try {
          await _empezarDeteccion();
        } on Object {
          // Sin guia, pero la captura sigue.
        }
      }
    }
  }

  @override
  Future<void> liberar() async {
    final CameraController? c = _controlador;
    _controlador = null;
    try {
      if (c != null && c.value.isStreamingImages) await c.stopImageStream();
    } on Object {
      // Se esta cerrando de todos modos.
    }
    await c?.dispose();
    await _detector?.close();
    await _anchos.close();
  }
}
