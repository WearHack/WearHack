/// Comprueba la frontera entre movil y web.
///
/// Estos tests corren en la VM de Dart, donde `dart:io` existe, asi que ven la
/// implementacion de movil. La de web se comprueba de otra forma: si algo suyo
/// se rompiera, `flutter build web` fallaria en CI.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wearhack/platform/captura.dart';

void main() {
  test('en movil la captura se reporta disponible', () {
    expect(crearGarmentPipeline().disponible, isTrue);
    expect(crearFaceCropper().disponible, isTrue);
  });

  test('los stubs de movil avisan de que no estan implementados', () async {
    final GarmentPipeline pipeline = crearGarmentPipeline();

    await expectLater(pipeline.preparar(), throwsUnimplementedError);
    await expectLater(
      pipeline.procesar(Uint8List(0)),
      throwsUnimplementedError,
    );
  });

  test('CapturaNoDisponible dice cual es el detalle', () {
    const fallo = CapturaNoDisponible('solo en movil');

    expect(fallo.toString(), contains('solo en movil'));
  });
}
