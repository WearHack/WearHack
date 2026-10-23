/// Lo que las pantallas necesitan del exterior, reunido en un solo objeto.
///
/// Todo lo que toca una plataforma (camara, informacion del dispositivo, hoja de
/// compartir) entra por aqui como interfaz o funcion, de modo que las pantallas
/// no importan ningun plugin y se prueban con piezas falsas.
library;

import 'dart:io';

import 'package:wearhack/features/captura_pruebas/almacen_capturas.dart';
import 'package:wearhack/features/captura_pruebas/modelos.dart';
import 'package:wearhack/features/captura_pruebas/servicio_captura.dart';
import 'package:wearhack/features/captura_pruebas/ui/camara.dart';
import 'package:wearhack/features/captura_pruebas/ui/guia_de_distancia.dart';

/// Lo que se lee solo del celular, para el JSON de cada toma.
class InfoDelDispositivo {
  const InfoDelDispositivo({
    required this.modelo,
    required this.sistema,
    required this.buildApp,
  });

  final String modelo;
  final String sistema;
  final String buildApp;
}

abstract interface class LectorDeDispositivo {
  Future<InfoDelDispositivo> leer();
}

/// Comparte el zip por la hoja de compartir del sistema (AirDrop, USB, ...).
typedef Compartir = Future<void> Function(File zip);

/// Borra las copias del zip que la hoja de compartir deja fuera del almacen
/// (en Android, `cache/share_plus/`). Se llama despues de Borrar: el zip lleva la
/// foto y el recorte, asi que esa copia no puede sobrevivir al lote.
typedef LimpiarTemporales = Future<void> Function();

class DependenciasCaptura {
  const DependenciasCaptura({
    required this.almacen,
    required this.servicio,
    required this.crearCamara,
    required this.dispositivo,
    required this.compartir,
    this.limpiarTemporales = _nadaQueLimpiar,
    this.ahora = DateTime.now,
    this.rangoDeDistancia = rangoDeDistanciaDelEntorno,
  });

  final AlmacenCapturas almacen;
  final ServicioCapturaPruebas servicio;
  final CamaraDeCaptura Function() crearCamara;
  final LectorDeDispositivo dispositivo;
  final Compartir compartir;
  final LimpiarTemporales limpiarTemporales;
  final DateTime Function() ahora;

  /// Rango de distancia calibrado de un celular, o `null` si no lo esta. Por
  /// defecto, el de los `--dart-define`.
  final RangoDeAncho? Function(CodigoCelular celular) rangoDeDistancia;
}

Future<void> _nadaQueLimpiar() async {}
