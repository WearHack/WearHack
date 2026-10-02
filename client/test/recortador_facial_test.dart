/// Comprueba el recorte facial completo con un detector falso.
///
/// Todas las fotos son sinteticas y se generan en memoria: ninguna foto de
/// calibracion, ni parecida, entra al repositorio.
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wearhack/core/color/conversion.dart';
import 'package:wearhack/core/color/perfil_icc.dart';
import 'package:wearhack/core/recorte/configuracion_recorte.dart';
import 'package:wearhack/core/recorte/recortador_facial.dart';

import 'helpers/icc_sintetico.dart';

ConfiguracionRecorte _config({
  double superior = 0.5,
  double inferior = 0.25,
  double lateral = 0.5,
  int ladoMaximo = 1280,
  int? anchoMinimo,
  double? maxQuemados,
}) => ConfiguracionRecorte(
  margenSuperior: superior,
  margenInferior: inferior,
  margenLateral: lateral,
  anchoMinimoRostroPx: anchoMinimo,
  maxQuemadosPct: maxQuemados,
  ladoMaximoDeteccion: ladoMaximo,
);

(int, int, int) _pixel(img.Image im, int x, int y) {
  final img.Pixel p = im.getPixel(x, y);
  return (p.r.toInt(), p.g.toInt(), p.b.toInt());
}

bool _contiene(Uint8List bytes, String texto) {
  final List<int> aguja = texto.codeUnits;
  for (int i = 0; i + aguja.length <= bytes.length; i++) {
    bool ok = true;
    for (int k = 0; k < aguja.length; k++) {
      if (bytes[i + k] != aguja[k]) {
        ok = false;
        break;
      }
    }
    if (ok) return true;
  }
  return false;
}

void main() {
  const CajaRostro cajaCentral = CajaRostro(
    left: 100,
    top: 100,
    width: 200,
    height: 200,
  );

  group('orientacion', () {
    test('la foto con EXIF 6 llega vertical al detector', () async {
      // Apaisada de 600x400 con una marca roja arriba a la izquierda. Con la
      // orientacion 6 (girar 90 grados a la derecha) queda 400x600 y la marca
      // pasa arriba a la derecha.
      final Uint8List foto = jpegSintetico(
        600,
        400,
        orientacion: 6,
        color: (int x, int y) =>
            (x < 150 && y < 150) ? (230, 30, 30) : (128, 128, 128),
      );
      final DetectorFalso detector = DetectorFalso(<CajaRostro>[cajaCentral]);

      await RecortadorFacial(
        detector: detector,
        configuracion: _config(),
      ).recortar(foto);

      final img.Image visto = img.decodeJpg(detector.recibido!)!;
      expect((visto.width, visto.height), (400, 600));
      final (int r, int g, int _) = _pixel(visto, 350, 50);
      expect(
        r,
        greaterThan(180),
        reason: 'la marca roja esta arriba a la derecha',
      );
      expect(g, lessThan(90));
      final (int r2, int g2, int _) = _pixel(visto, 50, 50);
      expect(
        (r2 - g2).abs(),
        lessThan(20),
        reason: 'arriba a la izquierda es gris',
      );
    });

    // Una marca roja en la esquina superior izquierda de la foto cruda. Segun el
    // estandar EXIF, cada orientacion la lleva a un sitio y puede intercambiar
    // el ancho y el alto.
    for (final (int, String, bool) caso in <(int, String, bool)>[
      (1, 'arriba-izquierda', false),
      (2, 'arriba-derecha', false),
      (3, 'abajo-derecha', false),
      (4, 'abajo-izquierda', false),
      (5, 'arriba-izquierda', true),
      (6, 'arriba-derecha', true),
      (7, 'abajo-derecha', true),
      (8, 'abajo-izquierda', true),
    ]) {
      test('EXIF ${caso.$1}: la marca queda ${caso.$2}', () async {
        final Uint8List foto = jpegSintetico(
          600,
          400,
          orientacion: caso.$1,
          color: (int x, int y) =>
              (x < 150 && y < 150) ? (230, 30, 30) : (128, 128, 128),
        );
        final DetectorFalso detector = DetectorFalso(<CajaRostro>[cajaCentral]);

        await RecortadorFacial(
          detector: detector,
          configuracion: _config(),
        ).recortar(foto);

        final img.Image visto = img.decodeJpg(detector.recibido!)!;
        expect(
          (visto.width, visto.height),
          caso.$3 ? (400, 600) : (600, 400),
          reason: 'dimensiones',
        );
        final int cerca = 50;
        final int x = caso.$2.endsWith('izquierda')
            ? cerca
            : visto.width - cerca;
        final int y = caso.$2.startsWith('arriba')
            ? cerca
            : visto.height - cerca;
        final (int r, int g, int _) marca = _pixel(visto, x, y);
        expect(
          marca.$1,
          greaterThan(180),
          reason: 'la marca roja esta en ${caso.$2}',
        );
        expect(marca.$2, lessThan(90));
        // Y la esquina opuesta es gris.
        final (int r2, int g2, int _) opuesta = _pixel(
          visto,
          visto.width - x,
          visto.height - y,
        );
        expect((opuesta.$1 - opuesta.$2).abs(), lessThan(20));
      });
    }

    test('la copia del detector no lleva perfil ni EXIF', () async {
      final Uint8List foto = jpegConIcc(
        jpegSintetico(300, 300, orientacion: 3),
        perfilDisplayP3(),
      );
      final DetectorFalso detector = DetectorFalso(<CajaRostro>[cajaCentral]);

      await RecortadorFacial(
        detector: detector,
        configuracion: _config(),
      ).recortar(foto);

      expect(_contiene(detector.recibido!, 'ICC_PROFILE'), isFalse);
      expect(_contiene(detector.recibido!, 'Exif'), isFalse);
    });
  });

  group('geometria', () {
    test(
      'lleva el recuadro del detector a la foto completa y aplica margenes',
      () async {
        final Uint8List foto = jpegSintetico(1000, 1000);
        final DetectorFalso detector = DetectorFalso(<CajaRostro>[
          const CajaRostro(left: 100, top: 150, width: 100, height: 120),
        ]);

        final RecorteFacial? r = await RecortadorFacial(
          detector: detector,
          configuracion: _config(ladoMaximo: 500),
        ).recortar(foto);

        final img.Image visto = img.decodeJpg(detector.recibido!)!;
        expect(
          (visto.width, visto.height),
          (500, 500),
          reason: 'reducida a la mitad',
        );
        // En la foto completa el rostro es (200, 300, 200 x 240).
        expect(r!.caja.left, closeTo(200, 0.01));
        expect(r.caja.top, closeTo(300, 0.01));
        expect(r.anchoRostroPx, 200);
        // x: 200 - 100 = 100 hasta 400 + 100 = 500.  y: 300 - 120 = 180 hasta 540 + 60 = 600.
        expect((r.ancho, r.alto), (400, 420));
        expect(r.margenSuperiorPx, 120);
        final img.Image png = img.decodePng(r.png)!;
        expect((png.width, png.height), (400, 420));
      },
    );

    test('un rostro pegado al borde recibe menos margen y lo dice', () async {
      final Uint8List foto = jpegSintetico(1000, 1000);
      final DetectorFalso detector = DetectorFalso(<CajaRostro>[
        const CajaRostro(left: 10, top: 5, width: 100, height: 120),
      ]);

      final RecorteFacial? r = await RecortadorFacial(
        detector: detector,
        configuracion: _config(ladoMaximo: 500),
      ).recortar(foto);

      // Pedia 120 px sobre el rostro; la foto solo da 10.
      expect(r!.margenSuperiorPx, 10);
      expect(r.caja.top, closeTo(10, 0.01));
    });

    test('el recorte no se sale de la foto por ningun lado', () async {
      final Uint8List foto = jpegSintetico(400, 400);
      final DetectorFalso detector = DetectorFalso(<CajaRostro>[
        const CajaRostro(left: 250, top: 250, width: 140, height: 140),
      ]);

      final RecorteFacial? r = await RecortadorFacial(
        detector: detector,
        configuracion: _config(superior: 2, inferior: 2, lateral: 2),
      ).recortar(foto);

      expect(r!.ancho, lessThanOrEqualTo(400));
      expect(r.alto, lessThanOrEqualTo(400));
      final img.Image png = img.decodePng(r.png)!;
      expect((png.width, png.height), (r.ancho, r.alto));
    });

    test('sin margenes el recorte es el recuadro', () async {
      final Uint8List foto = jpegSintetico(400, 400);
      final DetectorFalso detector = DetectorFalso(<CajaRostro>[cajaCentral]);

      final RecorteFacial? r = await RecortadorFacial(
        detector: detector,
        configuracion: _config(superior: 0, inferior: 0, lateral: 0),
      ).recortar(foto);

      expect((r!.ancho, r.alto), (200, 200));
      expect(r.margenSuperiorPx, 0);
    });
  });

  group('color', () {
    test('Display P3 se convierte a sRGB y el PNG no lleva perfil', () async {
      final Uint8List foto = jpegConIcc(
        jpegSintetico(400, 400, color: (int x, int y) => (200, 150, 120)),
        perfilDisplayP3(descripcion: tagDescV2('Display P3')),
      );
      final (int, int, int) crudo = _pixel(img.decodeJpg(foto)!, 200, 200);
      final PerfilRgb p3 = PerfilRgb.desdeBytes(perfilDisplayP3());
      final ({int r, int g, int b}) esperado = perfilASrgb8(
        p3,
        crudo.$1,
        crudo.$2,
        crudo.$3,
      );

      final RecorteFacial? r = await RecortadorFacial(
        detector: DetectorFalso(<CajaRostro>[cajaCentral]),
        configuracion: _config(),
      ).recortar(foto);

      final (int, int, int) salida = _pixel(
        img.decodePng(r!.png)!,
        r.ancho ~/ 2,
        r.alto ~/ 2,
      );
      expect(salida.$1, closeTo(esperado.r, 1));
      expect(salida.$2, closeTo(esperado.g, 1));
      expect(salida.$3, closeTo(esperado.b, 1));
      // La prueba solo vale si la conversion cambia el color de verdad.
      final int cambio =
          (salida.$1 - crudo.$1).abs() +
          (salida.$2 - crudo.$2).abs() +
          (salida.$3 - crudo.$3).abs();
      expect(cambio, greaterThanOrEqualTo(6));

      expect(r.perfilOrigen, 'Display P3');
      expect(r.perfilOrigenSupuesto, isFalse);
      expect(r.perfilRecorte, perfilDelRecorte);
      expect(_contiene(r.png, 'iCCP'), isFalse);
      expect(_contiene(r.png, 'sRGB'), isFalse);
    });

    test(
      'sin perfil se asume sRGB, no se toca ningun byte y queda anotado',
      () async {
        final Uint8List foto = jpegSintetico(
          400,
          400,
          color: (int x, int y) => (200, 150, 120),
        );
        final (int, int, int) crudo = _pixel(img.decodeJpg(foto)!, 200, 200);

        final RecorteFacial? r = await RecortadorFacial(
          detector: DetectorFalso(<CajaRostro>[cajaCentral]),
          configuracion: _config(),
        ).recortar(foto);

        expect(
          _pixel(img.decodePng(r!.png)!, r.ancho ~/ 2, r.alto ~/ 2),
          crudo,
        );
        expect(r.perfilOrigenSupuesto, isTrue);
        expect(r.perfilOrigen, contains('sin perfil'));
      },
    );

    test('un perfil con nombre ilegible se anota como sin nombre', () async {
      final Uint8List foto = jpegConIcc(
        jpegSintetico(300, 300),
        perfilDisplayP3(),
      );

      final RecorteFacial? r = await RecortadorFacial(
        detector: DetectorFalso(<CajaRostro>[cajaCentral]),
        configuracion: _config(),
      ).recortar(foto);

      expect(r!.perfilOrigen, 'perfil ICC sin nombre');
    });

    test(
      'un perfil que no se sabe leer falla en voz alta, no se adivina',
      () async {
        final Uint8List lut = construirPerfil(
          rojo: PerfilRgb.srgb.rojo,
          verde: PerfilRgb.srgb.verde,
          azul: PerfilRgb.srgb.azul,
          curva: curvaSrgbParametrica(),
          incluirMatriz: false,
        );
        final Uint8List foto = jpegConIcc(jpegSintetico(300, 300), lut);

        await expectLater(
          RecortadorFacial(
            detector: DetectorFalso(<CajaRostro>[cajaCentral]),
            configuracion: _config(),
          ).recortar(foto),
          throwsA(isA<PerfilIccNoSoportado>()),
        );
      },
    );
  });

  group('deteccion', () {
    test('sin rostros devuelve null', () async {
      final DetectorFalso detector = DetectorFalso(<CajaRostro>[]);

      final RecorteFacial? r = await RecortadorFacial(
        detector: detector,
        configuracion: _config(),
      ).recortar(jpegSintetico(300, 300));

      expect(r, isNull);
      expect(detector.llamadas, 1);
    });

    test(
      'recuadros inservibles (ancho cero, NaN) cuentan como sin rostro',
      () async {
        final RecorteFacial? r = await RecortadorFacial(
          detector: DetectorFalso(<CajaRostro>[
            const CajaRostro(left: 10, top: 10, width: 0, height: 50),
            const CajaRostro(left: double.nan, top: 10, width: 50, height: 50),
          ]),
          configuracion: _config(),
        ).recortar(jpegSintetico(300, 300));

        expect(r, isNull);
      },
    );

    test('con varios rostros se usa el mas grande y se avisa', () async {
      final RecorteFacial? r = await RecortadorFacial(
        detector: DetectorFalso(<CajaRostro>[
          const CajaRostro(left: 10, top: 10, width: 40, height: 40),
          const CajaRostro(left: 100, top: 100, width: 120, height: 120),
          const CajaRostro(left: 20, top: 200, width: 60, height: 60),
        ]),
        configuracion: _config(),
      ).recortar(jpegSintetico(400, 400));

      expect(r!.variosRostros, isTrue);
      expect(r.caja.width, 120);
    });

    test('con un solo rostro no se avisa de varios', () async {
      final RecorteFacial? r = await RecortadorFacial(
        detector: DetectorFalso(<CajaRostro>[cajaCentral]),
        configuracion: _config(),
      ).recortar(jpegSintetico(400, 400));

      expect(r!.variosRostros, isFalse);
    });
  });

  group('entrada invalida', () {
    test('algo que no es un JPEG falla con FormatException', () async {
      await expectLater(
        RecortadorFacial(
          detector: DetectorFalso(<CajaRostro>[cajaCentral]),
          configuracion: _config(),
        ).recortar(Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6])),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('calidad', () {
    test(
      'una foto quemada con umbral marca el control y da la recomendacion',
      () async {
        final RecorteFacial? r =
            await RecortadorFacial(
              detector: DetectorFalso(<CajaRostro>[cajaCentral]),
              configuracion: _config(maxQuemados: 5, anchoMinimo: 500),
            ).recortar(
              jpegSintetico(400, 400, color: (int x, int y) => (255, 255, 255)),
            );

        expect(r!.controles.porcentajeQuemados, greaterThan(90));
        expect(r.controles.pasa, isFalse);
        expect(r.controles.recomendaciones, hasLength(2));
        expect(r.controles.anchoRostroPx, 200);
      },
    );

    test('el mismo recorte sin umbrales no falla nunca', () async {
      final RecorteFacial? r =
          await RecortadorFacial(
            detector: DetectorFalso(<CajaRostro>[cajaCentral]),
            configuracion: _config(),
          ).recortar(
            jpegSintetico(400, 400, color: (int x, int y) => (255, 255, 255)),
          );

      expect(r!.controles.pasa, isTrue);
      expect(
        r.controles.porcentajeQuemados,
        greaterThan(90),
        reason: 'se mide igual',
      );
    });
  });

  group('reproducibilidad', () {
    test('la misma foto da exactamente los mismos bytes', () async {
      final Uint8List foto = jpegConIcc(
        jpegSintetico(
          500,
          500,
          color: (int x, int y) => ((x * 255) ~/ 500, (y * 255) ~/ 500, 90),
        ),
        perfilDisplayP3(),
      );
      RecortadorFacial nuevo() => RecortadorFacial(
        detector: DetectorFalso(<CajaRostro>[cajaCentral]),
        configuracion: _config(),
      );

      final RecorteFacial? a = await nuevo().recortar(foto);
      final RecorteFacial? b = await nuevo().recortar(foto);

      expect(a!.png, b!.png);
    });

    test('en un isolate aparte el resultado es identico', () async {
      final Uint8List foto = jpegConIcc(
        jpegSintetico(
          500,
          500,
          color: (int x, int y) => ((x * 255) ~/ 500, (y * 255) ~/ 500, 90),
        ),
        perfilDisplayP3(),
      );

      final RecorteFacial? mismo = await RecortadorFacial(
        detector: DetectorFalso(<CajaRostro>[cajaCentral]),
        configuracion: _config(),
      ).recortar(foto);
      final RecorteFacial? aparte = await RecortadorFacial(
        detector: DetectorFalso(<CajaRostro>[cajaCentral]),
        configuracion: _config(),
        ejecutor: <R>(tarea) => Isolate.run(tarea),
      ).recortar(foto);

      expect(aparte!.png, mismo!.png);
      expect(aparte.perfilOrigen, mismo.perfilOrigen);
    });
  });
}
