/// Piezas comunes de los tests del modo de captura de pruebas.
///
/// Todo es sintetico y vive en el directorio temporal del sistema: ninguna foto
/// de calibracion, ni parecida, entra al repositorio.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:wearhack/core/recorte/configuracion_recorte.dart';
import 'package:wearhack/core/recorte/recortador_facial.dart';
import 'package:wearhack/features/captura_pruebas/almacen_capturas.dart';
import 'package:wearhack/features/captura_pruebas/metadatos.dart';
import 'package:wearhack/features/captura_pruebas/modelos.dart';
import 'package:wearhack/platform/captura/contratos.dart';

import 'icc_sintetico.dart';

/// Crea una carpeta temporal fuera del repositorio.
Future<Directory> carpetaTemporal() =>
    Directory.systemTemp.createTemp('wearhack_captura_');

const ConfiguracionRecorte configuracionDePrueba = ConfiguracionRecorte(
  margenSuperior: 0.5,
  margenInferior: 0.25,
  margenLateral: 0.5,
);

const CajaRostro cajaDePrueba = CajaRostro(
  left: 100,
  top: 100,
  width: 150,
  height: 170,
);

IdToma idDe({
  String seudonimo = 'P3',
  Luz luz = Luz.ledc,
  CodigoCelular celular = CodigoCelular.d2,
  Repeticion repeticion = Repeticion.r1,
}) => IdToma(
  seudonimo: Seudonimo(seudonimo),
  luz: luz,
  celular: celular,
  repeticion: repeticion,
);

DatosDelCelular datosDelCelular({
  CodigoCelular codigo = CodigoCelular.d2,
  bool trueTone = false,
}) => DatosDelCelular(
  codigo: codigo,
  modelo: 'Modelo de prueba',
  sistema: 'Android 14',
  buildApp: '0.1.0+1',
  trueToneONightShift: trueTone,
);

/// Una foto sintetica en Display P3. `semilla` la hace distinta de otras.
Uint8List fotoDePrueba({int semilla = 0}) => jpegConIcc(
  jpegSintetico(
    400,
    400,
    color: (int x, int y) => (
      (x * 200 ~/ 400 + semilla * 7) % 256,
      (y * 200 ~/ 400 + semilla * 13) % 256,
      90 + semilla % 100,
    ),
  ),
  perfilDisplayP3(descripcion: tagDescV2('Display P3')),
);

/// El recorte real del producto con un detector falso.
RecortadorFacial recortadorReal({List<CajaRostro>? cajas}) => RecortadorFacial(
  detector: DetectorFalso(cajas ?? <CajaRostro>[cajaDePrueba]),
  configuracion: configuracionDePrueba,
);

/// Un [FaceCropper] que usa el recorte real y cuenta sus llamadas.
class CropperDePrueba implements FaceCropper {
  CropperDePrueba({List<CajaRostro>? cajas})
    : _real = recortadorReal(cajas: cajas);

  final RecortadorFacial _real;
  int llamadas = 0;
  Uint8List? ultimaEntrada;

  @override
  bool get disponible => true;

  @override
  Future<RecorteFacial?> recortar(Uint8List foto) {
    llamadas++;
    ultimaEntrada = foto;
    return _real.recortar(foto);
  }
}

/// Los archivos (no carpetas) bajo [dir], como rutas relativas.
Future<List<String>> archivosBajo(Directory dir) async {
  if (!await dir.exists()) return <String>[];
  final List<String> rutas = <String>[
    await for (final FileSystemEntity e in dir.list(recursive: true))
      if (e is File) e.path.substring(dir.path.length + 1),
  ];
  rutas.sort();
  return rutas;
}

/// Guarda `n` tomas distintas y devuelve el almacen.
Future<AlmacenCapturas> almacenConTomas(Directory raiz, int n) async {
  final AlmacenCapturas almacen = AlmacenCapturas(raiz);
  final CropperDePrueba cropper = CropperDePrueba();
  const List<Luz> luces = Luz.values;
  for (int i = 0; i < n; i++) {
    final Luz luz = luces[i % luces.length];
    final Repeticion rep = Repeticion.values[(i ~/ luces.length) % 3];
    final Uint8List foto = fotoDePrueba(semilla: i);
    final RecorteFacial recorte = (await cropper.recortar(foto))!;
    await almacen.guardarToma(
      id: idDe(luz: luz, repeticion: rep),
      foto: foto,
      extensionFoto: 'jpg',
      recorte: recorte,
      celular: datosDelCelular(),
      parametrosCamara: const ParametrosDeCamara(),
      momento: DateTime.utc(2026, 10, 15, 20, 42, 7),
    );
  }
  return almacen;
}
