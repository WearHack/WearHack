/// Piezas para probar las pantallas del modo de captura sin un telefono.
///
/// La camara es falsa y entrega fotos sinteticas; el almacen y el recorte son
/// los reales (en el directorio temporal del sistema), de modo que se prueba el
/// flujo completo, de la pulsacion al archivo en disco.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wearhack/features/captura_pruebas/almacen_capturas.dart';
import 'package:wearhack/features/captura_pruebas/modelos.dart';
import 'package:wearhack/features/captura_pruebas/servicio_captura.dart';
import 'package:wearhack/features/captura_pruebas/ui/camara.dart';
import 'package:wearhack/features/captura_pruebas/ui/dependencias.dart';
import 'package:wearhack/features/captura_pruebas/ui/guia_de_distancia.dart';
import 'package:wearhack/features/captura_pruebas/ui/pantalla_inicio.dart';
import 'package:wearhack/platform/captura/contratos.dart';

import 'captura_helpers.dart';

/// Una camara que no es una camara: entrega fotos sinteticas y cuenta lo que
/// le piden.
class CamaraFalsa implements CamaraDeCaptura {
  CamaraFalsa({
    this.falloAlAbrir,
    this.guiaActiva = false,
    this.fotos,
    this.retener,
  });

  /// Si se da, `inicializar` lanza esto.
  final Object? falloAlAbrir;

  final bool guiaActiva;

  /// Las fotos que entrega, en orden. Si faltan, una sintetica distinta cada vez.
  final List<Uint8List>? fotos;

  /// Si se da, `tomarFoto` espera a que se complete: para probar el doble toque.
  final Completer<void>? retener;

  bool abierta = false;
  bool liberada = false;
  int fotosTomadas = 0;
  final StreamController<int?> anchos = StreamController<int?>.broadcast();

  @override
  bool get guiaDeDistanciaActiva => guiaActiva;

  @override
  Stream<int?> get anchoDelRostroEnVivo => anchos.stream;

  @override
  Future<void> inicializar() async {
    if (falloAlAbrir != null) throw falloAlAbrir!;
    abierta = true;
  }

  @override
  Widget vistaPrevia() =>
      const SizedBox(key: Key('vista_previa'), width: 100, height: 100);

  @override
  Future<FotoTomada> tomarFoto() async {
    fotosTomadas++;
    if (retener != null) await retener!.future;
    final Uint8List bytes = (fotos != null && fotosTomadas <= fotos!.length)
        ? fotos![fotosTomadas - 1]
        : fotoDePrueba(semilla: fotosTomadas);
    return FotoTomada(bytes: bytes, extension: 'jpg');
  }

  @override
  Future<void> liberar() async {
    liberada = true;
    await anchos.close();
  }
}

class LectorFalso implements LectorDeDispositivo {
  const LectorFalso();

  @override
  Future<InfoDelDispositivo> leer() async => const InfoDelDispositivo(
    modelo: 'Celular de prueba',
    sistema: 'Android 14',
    buildApp: '0.1.0+1',
  );
}

/// Un [FaceCropper] con una configuracion de recorte propia.
class CropperConConfiguracion implements FaceCropper {
  CropperConConfiguracion(this._real);

  final Future<RecorteFacial?> Function(Uint8List) _real;

  @override
  bool get disponible => true;

  @override
  Future<RecorteFacial?> recortar(Uint8List foto) => _real(foto);
}

/// Un cropper que siempre falla con [error].
class CropperQueFalla implements FaceCropper {
  CropperQueFalla(this.error);

  final Object error;

  @override
  bool get disponible => true;

  @override
  Future<RecorteFacial?> recortar(Uint8List foto) async => throw error;
}

class Montaje {
  Montaje({
    required this.raiz,
    required this.almacen,
    required this.camara,
    required this.compartidos,
    required this.dependencias,
  });

  final Directory raiz;
  final AlmacenCapturas almacen;
  final CamaraFalsa camara;
  final List<File> compartidos;
  final DependenciasCaptura dependencias;
}

/// Arma las dependencias con el almacen real en una carpeta temporal.
Future<Montaje> montar(
  WidgetTester tester, {
  CamaraFalsa? camara,
  FaceCropper? cropper,
  RangoDeAncho? Function(CodigoCelular)? rango,
  Future<void> Function(File)? compartir,
}) async {
  final Directory raiz = (await tester.runAsync(carpetaTemporal))!;
  addTearDown(() async {
    await tester.runAsync(() async {
      if (await raiz.exists()) await raiz.delete(recursive: true);
    });
  });
  final AlmacenCapturas almacen = AlmacenCapturas(raiz);
  final CamaraFalsa cam = camara ?? CamaraFalsa();
  final List<File> compartidos = <File>[];
  final DependenciasCaptura dependencias = DependenciasCaptura(
    almacen: almacen,
    servicio: ServicioCapturaPruebas(
      almacen: almacen,
      cropper: cropper ?? CropperDePrueba(),
    ),
    crearCamara: () => cam,
    dispositivo: const LectorFalso(),
    compartir: compartir ?? (File f) async => compartidos.add(f),
    ahora: () => DateTime.utc(2026, 10, 15, 20, 42, 7),
    rangoDeDistancia: rango ?? (CodigoCelular c) => null,
  );
  return Montaje(
    raiz: raiz,
    almacen: almacen,
    camara: cam,
    compartidos: compartidos,
    dependencias: dependencias,
  );
}

/// Una pantalla de telefono, para que nada se salga ni se oculte.
void pantallaDeTelefono(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Deja avanzar la entrada y salida real (archivos, isolates) y vuelve a pintar.
///
/// `testWidgets` corre con un reloj falso: el codigo de la app vive en esa zona
/// y cada `await` de disco real solo avanza cuando se le da tiempo real
/// (`runAsync`) Y se bombea la zona (`pump`). Una cadena larga, como guardar tres
/// archivos o armar un zip, necesita muchas rondas de las dos cosas.
Future<void> asentar(WidgetTester tester, {int rondas = 6}) async {
  for (int i = 0; i < rondas; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Repite [asentar] hasta que [condicion] se cumpla o se acabe el tiempo.
Future<void> esperarHasta(
  WidgetTester tester,
  bool Function() condicion, {
  String? motivo,
}) async {
  for (int i = 0; i < 400; i++) {
    if (condicion()) return;
    await asentar(tester, rondas: 1);
  }
  fail(motivo ?? 'La condicion no se cumplio a tiempo');
}

Future<void> elegir(WidgetTester tester, Key campo, String texto) async {
  await tester.tap(find.byKey(campo));
  await tester.pumpAndSettle();
  await tester.tap(find.text(texto).last);
  await tester.pumpAndSettle();
}

/// Abre la app en la pantalla de inicio.
Future<void> abrirInicio(WidgetTester tester, Montaje m) async {
  pantallaDeTelefono(tester);
  await tester.pumpWidget(
    MaterialApp(home: PantallaInicioCaptura(dependencias: m.dependencias)),
  );
  await asentar(tester);
}

/// Rellena el inicio y llega a la cuadricula.
Future<void> llegarALaCuadricula(
  WidgetTester tester,
  Montaje m, {
  String persona = 'P3',
  String celular = 'D2 - Android gama baja',
}) async {
  await abrirInicio(tester, m);
  await elegir(tester, const Key('campo_seudonimo'), persona);
  await elegir(tester, const Key('campo_celular'), celular);
  await tester.tap(find.byKey(const Key('casilla_autorizacion')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('boton_continuar')));
  // No pumpAndSettle: la cuadricula muestra un indicador de carga que gira hasta
  // que termina la lectura real del disco, y pumpAndSettle espera a que pare.
  await tester.pump();
  await esperarHasta(
    tester,
    () => find.byKey(const Key('resumen')).evaluate().isNotEmpty,
    motivo: 'La cuadricula no termino de cargar',
  );
}

/// Toca una casilla y toma la foto, hasta volver a la cuadricula.
Future<void> capturarCasilla(
  WidgetTester tester,
  String luz,
  String repeticion,
) async {
  await tester.tap(find.byKey(Key('celda_${luz}_$repeticion')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('boton_capturar')));
  await esperarHasta(
    tester,
    () => find.byKey(const Key('resumen')).evaluate().isNotEmpty,
    motivo: 'No se volvio a la cuadricula despues de capturar',
  );
  // Ya se ve la cuadricula, pero todavia esta releyendo las tomas del disco.
  await asentar(tester, rondas: 20);
}
