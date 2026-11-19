/// La tabla ISCC-NBS (#58): que el asset este completo, que ΔE00 este bien y
/// que colores conocidos caigan en su categoria.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wearhack/core/atributos_c18.dart';
import 'package:wearhack/core/color/categoria_color.dart';
import 'package:wearhack/core/color/conversion.dart';
import 'package:wearhack/core/color/perfil_icc.dart';
import 'package:wearhack/core/vocabulario.dart';
import 'package:wearhack/features/closet/captura/item_cola.dart';

ColorLab _lab(int r, int g, int b) => perfilALab(PerfilRgb.srgb, r, g, b);

ColorLab _l(double l, double a, double b) => ColorLab(l: l, a: a, b: b);

void main() {
  final TablaIsccNbs tabla = TablaIsccNbs.desdeJson(
    File(assetTablaIsccNbs).readAsStringSync(),
  );

  group('tabla', () {
    test('tiene los 267 bloques, en orden', () {
      expect(tabla.bloques.map((BloqueIsccNbs b) => b.numero), <int>[
        for (int i = 1; i <= 267; i++) i,
      ]);
    });

    test('usa las 20 categorias del Core y ninguna mas', () {
      final Set<CategoriaColor> usadas = <CategoriaColor>{
        for (final BloqueIsccNbs b in tabla.bloques) b.categoria,
      };
      expect(usadas, <CategoriaColor>{
        for (final CategoriaColor c in CategoriaColor.values)
          if (c != CategoriaColor.multicolor) c,
      });
    });

    test('un centroide cae en su propio bloque', () {
      for (final BloqueIsccNbs b in tabla.bloques) {
        expect(tabla.bloqueMasCercano(b.lab).numero, b.numero);
      }
    });
  });

  test('los codigos son los del Core', () {
    expect(CategoriaColor.verdeOliva.codigo, 'VERDE_OLIVA');
    expect(CategoriaColor.azulMarino.codigo, 'AZUL_MARINO');
    expect(CategoriaColor.desdeCodigo('CAFE'), CategoriaColor.cafe);
    expect(() => CategoriaColor.desdeCodigo('MARRON'), throwsFormatException);
  });

  test('la cola de captura traduce los nombres de antes (#58)', () {
    for (final (String viejo, CategoriaColor nueva)
        in <(String, CategoriaColor)>[
          ('marron', CategoriaColor.cafe),
          ('rosa', CategoriaColor.rosado),
          ('azul', CategoriaColor.azul),
        ]) {
      final Map<String, Object?> json = const DatosPrenda(
        tipo: TipoC18.camiseta,
        confianzaTipo: 0.9,
        patron: PatronC18.liso,
        confianzaPatron: 0.9,
        textura: null,
        color: ColorLab(l: 40, a: 10, b: 20),
        categoriaColor: CategoriaColor.negro,
      ).toJson()..['categoria_color'] = viejo;
      expect(DatosPrenda.fromJson(json).categoriaColor, nueva);
    }
  });

  group('deltaE00', () {
    // Pares de la tabla de Sharma, Wu y Dalal (2005), con su ΔE00 publicado.
    final List<(ColorLab, ColorLab, double)>
    pares = <(ColorLab, ColorLab, double)>[
      (_l(50, 2.6772, -79.7751), _l(50, 0, -82.7485), 2.0425),
      (_l(50, -1.3802, -84.2814), _l(50, 0, -82.7485), 1.0000),
      (_l(50, 0, 0), _l(50, -1, 2), 2.3669),
      (_l(50, 2.49, -0.001), _l(50, -2.49, 0.0009), 7.1792),
      (_l(50, 2.5, 0), _l(73, 25, -18), 27.1492),
      (_l(60.2574, -34.0099, 36.2677), _l(60.4626, -34.1751, 39.4387), 1.2644),
      (_l(22.7233, 20.0904, -46.694), _l(23.0331, 14.973, -42.5619), 2.0373),
      (_l(90.9257, -0.5406, -0.9208), _l(88.6381, -0.8985, -0.7239), 1.5381),
    ];

    for (final (ColorLab x, ColorLab y, double esperado) in pares) {
      test('$x vs $y = $esperado', () {
        expect(deltaE00(x, y), closeTo(esperado, 1e-4));
        expect(deltaE00(y, x), closeTo(esperado, 1e-4));
      });
    }

    test('un color contra si mismo da 0', () {
      expect(deltaE00(_l(40, 10, -20), _l(40, 10, -20)), 0);
    });
  });

  group('categoria', () {
    final Map<CategoriaColor, List<List<int>>> referencias =
        <CategoriaColor, List<List<int>>>{
          CategoriaColor.negro: <List<int>>[
            <int>[0, 0, 0],
            <int>[25, 25, 25],
          ],
          CategoriaColor.blanco: <List<int>>[
            <int>[255, 255, 255],
            <int>[240, 240, 240],
          ],
          CategoriaColor.gris: <List<int>>[
            <int>[128, 128, 128],
            <int>[100, 100, 100],
            <int>[54, 69, 79], // gris carbon
          ],
          CategoriaColor.beige: <List<int>>[
            <int>[225, 198, 153],
            <int>[255, 253, 208], // crema
          ],
          CategoriaColor.cafe: <List<int>>[
            <int>[101, 67, 33],
            <int>[139, 69, 19],
          ],
          CategoriaColor.vinotinto: <List<int>>[
            <int>[128, 0, 32],
            <int>[114, 47, 55],
          ],
          CategoriaColor.rojo: <List<int>>[
            <int>[220, 20, 20],
            <int>[200, 0, 0],
            <int>[255, 0, 0],
          ],
          CategoriaColor.rosado: <List<int>>[
            <int>[255, 182, 193],
            <int>[255, 192, 203],
          ],
          CategoriaColor.fucsia: <List<int>>[
            <int>[228, 0, 124],
          ],
          CategoriaColor.naranja: <List<int>>[
            <int>[255, 140, 0],
            <int>[255, 165, 0],
          ],
          CategoriaColor.amarillo: <List<int>>[
            <int>[255, 230, 0],
            <int>[255, 255, 0],
          ],
          CategoriaColor.mostaza: <List<int>>[
            <int>[204, 153, 0],
          ],
          CategoriaColor.verdeOliva: <List<int>>[
            <int>[128, 128, 0],
            <int>[85, 107, 47],
          ],
          CategoriaColor.verde: <List<int>>[
            <int>[0, 128, 0],
            <int>[34, 139, 34],
          ],
          CategoriaColor.turquesa: <List<int>>[
            <int>[64, 224, 208],
            <int>[0, 206, 209],
          ],
          CategoriaColor.celeste: <List<int>>[
            <int>[135, 206, 235],
            <int>[173, 216, 230],
          ],
          CategoriaColor.azul: <List<int>>[
            <int>[0, 0, 255],
            <int>[30, 80, 200],
          ],
          CategoriaColor.azulMarino: <List<int>>[
            <int>[0, 0, 128],
            <int>[31, 42, 68],
          ],
          CategoriaColor.morado: <List<int>>[
            <int>[128, 0, 128],
            <int>[102, 51, 153],
          ],
          CategoriaColor.lila: <List<int>>[
            <int>[200, 162, 200],
          ],
        };

    referencias.forEach((CategoriaColor esperada, List<List<int>> colores) {
      test('${esperada.name}: $colores', () {
        for (final List<int> c in colores) {
          final ColorLab lab = _lab(c[0], c[1], c[2]);
          expect(
            tabla.categoria(lab),
            esperada,
            reason:
                'rgb(${c[0]}, ${c[1]}, ${c[2]}) cae en '
                '${tabla.bloqueMasCercano(lab).nombre}',
          );
        }
      });
    });

    test('nunca devuelve multicolor', () {
      for (int r = 0; r < 256; r += 51) {
        for (int g = 0; g < 256; g += 51) {
          for (int b = 0; b < 256; b += 51) {
            expect(
              tabla.categoria(_lab(r, g, b)),
              isNot(CategoriaColor.multicolor),
            );
          }
        }
      }
    });
  });
}
