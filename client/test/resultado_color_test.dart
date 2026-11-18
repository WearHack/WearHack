import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wearhack/core/color/conversion.dart';
import 'package:wearhack/core/color/perfil_icc.dart';
import 'package:wearhack/core/vocabulario.dart';
import 'package:wearhack/features/colorimetria/ui/resultado_color.dart';

Widget _app(Widget hijo, {bool reducir = false}) => MaterialApp(
  home: Builder(
    builder: (BuildContext context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reducir),
      child: Scaffold(body: hijo),
    ),
  ),
);

void main() {
  group('labASrgb8', () {
    test('es la inversa de pasar de sRGB a Lab', () {
      const List<List<int>> colores = <List<int>>[
        <int>[0, 0, 0],
        <int>[255, 255, 255],
        <int>[128, 128, 128],
        <int>[220, 20, 20],
        <int>[30, 144, 255],
        <int>[245, 245, 220],
        <int>[101, 67, 33],
        <int>[224, 172, 105],
      ];
      for (final List<int> c in colores) {
        final ({int r, int g, int b}) vuelta = labASrgb8(
          perfilALab(PerfilRgb.srgb, c[0], c[1], c[2]),
        );
        expect(vuelta.r, closeTo(c[0], 1), reason: 'rojo de $c');
        expect(vuelta.g, closeTo(c[1], 1), reason: 'verde de $c');
        expect(vuelta.b, closeTo(c[2], 1), reason: 'azul de $c');
      }
    });

    test('un Lab fuera del gamut se recorta sin fallar', () {
      final ({int r, int g, int b}) c = labASrgb8(
        const ColorLab(l: 50, a: 120, b: 120),
      );
      for (final int canal in <int>[c.r, c.g, c.b]) {
        expect(canal, inInclusiveRange(0, 255));
      }
    });
  });

  group('AnilloConfianza', () {
    testWidgets('cuenta desde cero hasta el valor', (tester) async {
      await tester.pumpWidget(_app(const AnilloConfianza(valor: 0.82)));
      expect(find.text('0 %'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('82 %'), findsOneWidget);
    });

    testWidgets('con reducir animaciones ya sale lleno', (tester) async {
      await tester.pumpWidget(
        _app(const AnilloConfianza(valor: 0.82), reducir: true),
      );
      expect(find.text('82 %'), findsOneWidget);
    });

    testWidgets('un valor fuera de rango se limita a 0 y 100', (tester) async {
      await tester.pumpWidget(
        _app(const AnilloConfianza(valor: 1.7), reducir: true),
      );
      expect(find.text('100 %'), findsOneWidget);
    });
  });

  group('MuestrasPerfil', () {
    const ColorLab lab = ColorLab(l: 60, a: 15, b: 20);

    testWidgets('solo dibuja lo que se midio', (tester) async {
      await tester.pumpWidget(
        _app(const MuestrasPerfil(piel: lab, iris: lab), reducir: true),
      );
      expect(find.text('Piel'), findsOneWidget);
      expect(find.text('Ojos'), findsOneWidget);
      expect(find.text('Cabello'), findsNothing);
    });

    testWidgets('sin ninguna medida no ocupa nada', (tester) async {
      await tester.pumpWidget(_app(const MuestrasPerfil(), reducir: true));
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('la muestra lleva el color medido', (tester) async {
      await tester.pumpWidget(
        _app(const MuestrasPerfil(piel: lab), reducir: true),
      );
      final Color esperado = MuestrasPerfil.aColor(lab);
      final bool hay = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .any(
            (DecoratedBox d) =>
                d.decoration is BoxDecoration &&
                (d.decoration as BoxDecoration).color == esperado,
          );
      expect(hay, isTrue);
    });
  });
}
