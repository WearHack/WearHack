/// El clasificador de prendas sin LiteRT (issue #13): la entrada que se le
/// prepara y como se leen sus salidas.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wearhack/core/atributos_c18.dart';
import 'package:wearhack/core/clasificacion/clasificador_prenda.dart';

/// Los valores RGB del pixel (x, y) de la entrada.
List<double> pixel(Float32List entrada, int x, int y) {
  final int i = (y * ladoEntradaClasificador + x) * 3;
  return <double>[entrada[i], entrada[i + 1], entrada[i + 2]];
}

img.Image rgba(int ancho, int alto, img.Color color) {
  final img.Image imagen = img.Image(
    width: ancho,
    height: alto,
    numChannels: 4,
  );
  img.fill(imagen, color: color);
  return imagen;
}

void main() {
  group('entrada', () {
    test('es 224 x 224 x 3 en [0, 255]', () {
      final Float32List entrada = entradaDelClasificador(
        rgba(300, 300, img.ColorRgba8(10, 20, 30, 255)),
      );
      expect(entrada.length, 224 * 224 * 3);
      expect(pixel(entrada, 112, 112), <double>[10, 20, 30]);
    });

    test('lo transparente se pinta de blanco', () {
      final Float32List entrada = entradaDelClasificador(
        rgba(224, 224, img.ColorRgba8(0, 0, 0, 0)),
      );
      expect(pixel(entrada, 0, 0), <double>[255, 255, 255]);
      expect(pixel(entrada, 223, 223), <double>[255, 255, 255]);
    });

    test('una prenda alargada se centra en un cuadrado blanco', () {
      // 112 de ancho por 224 de alto: queda una franja blanca de 56 a cada lado.
      final Float32List entrada = entradaDelClasificador(
        rgba(112, 224, img.ColorRgba8(200, 0, 0, 255)),
      );
      expect(pixel(entrada, 10, 112), <double>[255, 255, 255]);
      expect(pixel(entrada, 112, 112), <double>[200, 0, 0]);
      expect(pixel(entrada, 213, 112), <double>[255, 255, 255]);
    });

    test('lo semitransparente se mezcla con el blanco', () {
      final Float32List entrada = entradaDelClasificador(
        rgba(224, 224, img.ColorRgba8(0, 0, 0, 128)),
      );
      final double gris = pixel(entrada, 50, 50).first;
      expect(gris, inInclusiveRange(120, 135));
    });

    test('una imagen vacia se rechaza', () {
      expect(
        () => entradaDelClasificador(img.Image(width: 0, height: 0)),
        throwsArgumentError,
      );
    });
  });

  group('salidas', () {
    List<double> conMaximoEn(int n, int indice, {double logit = 5}) => <double>[
      for (int i = 0; i < n; i++) i == indice ? logit : 0,
    ];

    test('elige la clase con mas logit en cada cabeza', () {
      final Clasificacion c = leerSalidasDelClasificador(<List<double>>[
        conMaximoEn(21, 7),
        conMaximoEn(8, 1),
      ]);
      expect(c.tipo, TipoC18.pantalon);
      expect(c.patron, PatronC18.rayas);
    });

    test('las cabezas se reconocen por tamano, no por orden', () {
      final Clasificacion c = leerSalidasDelClasificador(<List<double>>[
        conMaximoEn(8, 4),
        conMaximoEn(21, 12),
      ]);
      expect(c.tipo, TipoC18.calzado);
      expect(c.patron, PatronC18.floral);
    });

    test('la confianza es la probabilidad tras softmax', () {
      final Clasificacion c = leerSalidasDelClasificador(<List<double>>[
        conMaximoEn(21, 0, logit: 2),
        <double>[0, 0, 0, 0, 0, 0, 0, 0],
      ]);
      final double esperada = math.exp(2) / (math.exp(2) + 20);
      expect(c.confianzaTipo, closeTo(esperada, 1e-9));
      expect(c.confianzaPatron, closeTo(1 / 8, 1e-9));
    });

    test('no se desborda con logits enormes', () {
      final Clasificacion c = leerSalidasDelClasificador(<List<double>>[
        conMaximoEn(21, 3, logit: 1000),
        conMaximoEn(8, 0, logit: 1000),
      ]);
      expect(c.confianzaTipo, closeTo(1, 1e-9));
      expect(c.tipo, TipoC18.cardigan);
    });

    test('salidas de otro tamano son un error claro', () {
      expect(
        () => leerSalidasDelClasificador(<List<double>>[
          List<double>.filled(20, 0),
          List<double>.filled(8, 0),
        ]),
        throwsFormatException,
      );
      expect(
        () => leerSalidasDelClasificador(<List<double>>[
          List<double>.filled(21, 0),
        ]),
        throwsFormatException,
      );
    });
  });

  group('orden de las clases', () {
    test('es el de mapeo.py del entrenamiento', () {
      expect(
        ordenTiposClasificador.map((TipoC18 t) => t.codigo).toList(),
        <String>[
          'CAMISA', 'CAMISETA', 'SUETER', 'CARDIGAN', 'CHAQUETA', 'ABRIGO',
          'CHALECO', 'PANTALON', 'SHORT', 'FALDA', 'VESTIDO', 'ENTERIZO',
          'CALZADO', 'GAFAS', 'SOMBRERO', 'ACCESORIO_CABELLO', 'CORBATA',
          'BUFANDA', 'RELOJ', 'CINTURON', 'BOLSO', //
        ],
      );
      expect(
        ordenPatronesClasificador.map((PatronC18 p) => p.codigo).toList(),
        <String>[
          'LISO', 'RAYAS', 'CUADROS', 'PUNTOS', 'FLORAL', 'ANIMAL',
          'GEOMETRICO', 'OTRO_ESTAMPADO', //
        ],
      );
    });

    test('la joyeria no sale del clasificador', () {
      expect(ordenTiposClasificador, isNot(contains(TipoC18.joyeria)));
    });

    test('los codigos se leen de vuelta', () {
      for (final TipoC18 t in TipoC18.values) {
        expect(TipoC18.deCodigo(t.codigo), t);
      }
      expect(() => TipoC18.deCodigo('jean'), throwsFormatException);
    });
  });
}
