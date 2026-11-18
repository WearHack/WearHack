/// El pipeline de una prenda con modelos falsos (issues #12 y #13): el orden de
/// los pasos y lo que sale.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wearhack/core/atributos_c18.dart';
import 'package:wearhack/core/clasificacion/clasificador_prenda.dart';
import 'package:wearhack/core/clasificacion/pipeline_prendas.dart';
import 'package:wearhack/core/color/categoria_color.dart';
import 'package:wearhack/core/color/color_base.dart';
import 'package:wearhack/core/vocabulario.dart';
import 'package:wearhack/platform/captura/contratos.dart';

class RemovedorFalso implements RemovedorDeFondo {
  RemovedorFalso(this.bitacora, this.prenda);

  final List<String> bitacora;
  final img.Image prenda;

  @override
  Future<img.Image> quitarFondo(Uint8List foto) async {
    bitacora.add('fondo');
    return prenda;
  }
}

class ClasificadorFalso implements ClasificadorDePrendas {
  ClasificadorFalso(this.bitacora);

  final List<String> bitacora;
  img.Image? recibida;

  @override
  Future<Clasificacion> clasificar(img.Image prendaSinFondo) async {
    bitacora.add('clasificar');
    recibida = prendaSinFondo;
    return const Clasificacion(
      tipo: TipoC18.camiseta,
      confianzaTipo: 0.91,
      patron: PatronC18.liso,
      confianzaPatron: 0.77,
    );
  }
}

ConfiguracionColorBase configuracion() =>
    ConfiguracionColorBase.desdeTextos(const <String, String>{
      'COLOR_METODO': 'moda',
      'COLOR_SOMBRAS_PCT': '0',
      'COLOR_BRILLOS_PCT': '0',
    });

/// Una camiseta azul de 20 x 20 en el centro de 40 x 40, el resto transparente.
img.Image camisetaAzul() {
  final img.Image imagen = img.Image(width: 40, height: 40, numChannels: 4);
  img.fill(imagen, color: img.ColorRgba8(0, 0, 0, 0));
  img.fillRect(
    imagen,
    x1: 10,
    y1: 10,
    x2: 29,
    y2: 29,
    color: img.ColorRgba8(20, 40, 160, 255),
  );
  return imagen;
}

Future<TablaIsccNbs> tablaColores() async =>
    TablaIsccNbs.desdeJson(File(assetTablaIsccNbs).readAsStringSync());

void main() {
  test(
    'quita el fondo, clasifica y saca el color de la prenda sin fondo',
    () async {
      final List<String> bitacora = <String>[];
      final ClasificadorFalso clasificador = ClasificadorFalso(bitacora);
      final img.Image sinFondo = camisetaAzul();
      final PipelinePrendasOnDevice pipeline = PipelinePrendasOnDevice(
        removedor: RemovedorFalso(bitacora, sinFondo),
        clasificador: clasificador,
        configuracionColor: configuracion,
        tablaColores: tablaColores,
      );

      await pipeline.preparar();
      final PrendaClasificada prenda = await pipeline.procesar(
        Uint8List.fromList(<int>[0xFF, 0xD8]),
      );
      await pipeline.liberar();

      expect(bitacora, <String>['fondo', 'clasificar']);
      expect(identical(clasificador.recibida, sinFondo), isTrue);
      expect(prenda.tipo, TipoC18.camiseta);
      expect(prenda.confianzaTipo, 0.91);
      expect(prenda.patron, PatronC18.liso);
      expect(prenda.textura, isNull);
      // Azul: b negativo. La categoria sale del mismo Lab.
      expect(prenda.color.b, lessThan(-30));
      expect(prenda.categoriaColor, CategoriaColor.azul);
    },
  );

  test('lo que se sube es el PNG sin fondo, nunca la foto que entro', () async {
    final List<String> bitacora = <String>[];
    final PipelinePrendasOnDevice pipeline = PipelinePrendasOnDevice(
      removedor: RemovedorFalso(bitacora, camisetaAzul()),
      clasificador: ClasificadorFalso(bitacora),
      configuracionColor: configuracion,
      tablaColores: tablaColores,
    );
    final Uint8List foto = Uint8List.fromList(<int>[0xFF, 0xD8, 1, 2, 3]);

    final PrendaClasificada prenda = await pipeline.procesar(foto);

    final img.Image? png = img.decodePng(prenda.imagenSinFondo);
    expect(png, isNotNull);
    expect(png!.numChannels, 4);
    expect(png.getPixel(0, 0).a, 0);
    expect(prenda.imagenSinFondo, isNot(foto));
  });

  test('sin u2netp falla en vez de dejar pasar la foto', () async {
    final PipelinePrendasOnDevice pipeline = PipelinePrendasOnDevice(
      removedor: const RemovedorDeFondoPendiente(),
      clasificador: ClasificadorFalso(<String>[]),
      configuracionColor: configuracion,
      tablaColores: tablaColores,
    );

    await expectLater(
      pipeline.procesar(Uint8List.fromList(<int>[0xFF, 0xD8])),
      throwsA(isA<CapturaNoDisponible>()),
    );
  });

  test(
    'una prenda sin pixeles opacos es un error, no un color inventado',
    () async {
      final img.Image vacia = img.Image(width: 10, height: 10, numChannels: 4);
      img.fill(vacia, color: img.ColorRgba8(0, 0, 0, 0));
      final PipelinePrendasOnDevice pipeline = PipelinePrendasOnDevice(
        removedor: RemovedorFalso(<String>[], vacia),
        clasificador: ClasificadorFalso(<String>[]),
        configuracionColor: configuracion,
        tablaColores: tablaColores,
      );

      await expectLater(
        pipeline.procesar(Uint8List.fromList(<int>[0xFF, 0xD8])),
        throwsA(isA<PrendaSinPixeles>()),
      );
    },
  );

  test(
    'sin configuracion de color falla al preparar, antes de los modelos',
    () async {
      final List<String> bitacora = <String>[];
      final PipelinePrendasOnDevice pipeline = PipelinePrendasOnDevice(
        removedor: RemovedorFalso(bitacora, camisetaAzul()),
        clasificador: ClasificadorFalso(bitacora),
        configuracionColor: () =>
            ConfiguracionColorBase.desdeTextos(const <String, String>{}),
        tablaColores: tablaColores,
      );

      await expectLater(
        pipeline.preparar(),
        throwsA(isA<ConfiguracionColorBaseInvalida>()),
      );
      expect(bitacora, isEmpty);
    },
  );
}
