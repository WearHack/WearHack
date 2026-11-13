/// Comprueba la frontera entre movil y web.
///
/// Estos tests corren en la VM de Dart, donde `dart:io` existe, asi que ven la
/// implementacion de movil. La de web se comprueba de otra forma: si algo suyo
/// se rompiera, `flutter build web` fallaria en CI.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wearhack/core/color/color_base.dart';
import 'package:wearhack/core/recorte/configuracion_recorte.dart';
import 'package:wearhack/platform/captura.dart';
import 'package:wearhack/platform/captura/captura_movil.dart'
    show FaceCropperMovil;

import 'helpers/icc_sintetico.dart';

void main() {
  test('en movil la captura se reporta disponible', () {
    expect(crearGarmentPipeline().disponible, isTrue);
    expect(crearFaceCropper().disponible, isTrue);
  });

  test(
    'sin los --dart-define del color base, el lote falla al preparar',
    () async {
      // Las pruebas no pasan COLOR_METODO y compania: es lo que pasaria en una
      // build sin configurar. Falla antes de cargar ningun modelo.
      final GarmentPipeline pipeline = crearGarmentPipeline();

      await expectLater(
        pipeline.preparar(),
        throwsA(isA<ConfiguracionColorBaseInvalida>()),
      );
    },
  );

  test('CapturaNoDisponible dice cual es el detalle', () {
    const fallo = CapturaNoDisponible('solo en movil');

    expect(fallo.toString(), contains('solo en movil'));
  });

  group('recorte facial en movil', () {
    test('de punta a punta, con el isolate que usa la app', () async {
      final FaceCropper cropper = FaceCropperMovil(
        detector: DetectorFalso(<CajaRostro>[
          const CajaRostro(left: 100, top: 100, width: 100, height: 100),
        ]),
        configuracion: const ConfiguracionRecorte(
          margenSuperior: 0.5,
          margenInferior: 0.25,
          margenLateral: 0.5,
        ),
      );

      final RecorteFacial? recorte = await cropper.recortar(
        jpegSintetico(400, 400),
      );

      expect(recorte, isNotNull);
      // x: 100-50=50 a 200+50=250; y: 100-50=50 a 200+25=225.
      expect((recorte!.ancho, recorte.alto), (200, 175));
      final img.Image png = img.decodePng(recorte.png)!;
      expect((png.width, png.height), (200, 175));
    });

    test('sin rostro devuelve null', () async {
      final FaceCropper cropper = FaceCropperMovil(
        detector: DetectorFalso(<CajaRostro>[]),
        configuracion: const ConfiguracionRecorte(
          margenSuperior: 0,
          margenInferior: 0,
          margenLateral: 0,
        ),
      );

      expect(await cropper.recortar(jpegSintetico(300, 300)), isNull);
    });
  });
}
