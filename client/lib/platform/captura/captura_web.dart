/// Implementacion para web. No hay captura.
///
/// En web WearHack es solo consulta y gestion. No hay camara ni interpretes, y
/// no es una limitacion temporal: correr u2netp y el clasificador en una
/// pestana significaria bajar decenas de megabytes de modelos y ejecutarlos con
/// mucho menos acelerador que en el telefono.
///
/// Este archivo es el que toma la build de web. Su valor esta en lo que **no**
/// importa: ni LiteRT, ni ML Kit, ni camara. Si algo de eso acaba en el bundle
/// de web, es que un import se colo fuera de esta frontera.
library;

import 'dart:typed_data';

import 'package:wearhack/features/closet/captura/captura_de_prendas.dart';
import 'package:wearhack/platform/captura/camara.dart';
import 'package:wearhack/platform/captura/contratos.dart';

class GarmentPipelineWeb implements GarmentPipeline {
  @override
  bool get disponible => false;

  @override
  Future<void> preparar() async {}

  @override
  Future<PrendaClasificada> procesar(Uint8List foto) async {
    throw const CapturaNoDisponible(
      'La clasificacion de prendas solo corre en movil.',
    );
  }

  @override
  Future<void> liberar() async {}
}

class FaceCropperWeb implements FaceCropper {
  @override
  bool get disponible => false;

  @override
  Future<RecorteFacial?> recortar(Uint8List foto) async {
    throw const CapturaNoDisponible(
      'El recorte de rostro solo corre en movil.',
    );
  }
}

GarmentPipeline crearGarmentPipeline() => GarmentPipelineWeb();

FaceCropper crearFaceCropper() => FaceCropperWeb();

/// En web no hay captura de prendas: la UI consulta `GarmentPipeline.disponible`
/// antes de llegar aqui, asi que esto solo corre si alguien se salta esa
/// comprobacion.
CamaraDeCaptura crearCamaraTrasera() {
  throw const CapturaNoDisponible('La camara solo existe en movil.');
}

Future<CapturaDePrendas> abrirCapturaDePrendas() async {
  throw const CapturaNoDisponible('La captura de prendas solo corre en movil.');
}
