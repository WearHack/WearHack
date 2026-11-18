import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wearhack/app/marca.dart';
import 'package:wearhack/core/vocabulario.dart';
import 'package:wearhack/features/closet/ui/silueta_prenda.dart';

void main() {
  group('SiluetaPrenda', () {
    test('cada tipo con silueta tiene una forma con area', () {
      for (final TipoPrenda tipo in TipoPrenda.values) {
        if (tipo == TipoPrenda.accesorio) continue;
        final Rect caja = formaDeSilueta(tipo).getBounds();
        expect(caja.isEmpty, isFalse, reason: '$tipo no tiene forma');
        expect(caja.left, greaterThanOrEqualTo(0), reason: '$tipo');
        expect(caja.top, greaterThanOrEqualTo(0), reason: '$tipo');
        expect(caja.right, lessThanOrEqualTo(100), reason: '$tipo');
        expect(caja.bottom, lessThanOrEqualTo(100), reason: '$tipo');
      }
    });

    test('las formas de camiseta, pantalon, falda y zapato son distintas', () {
      final List<Rect> cajas = <Rect>[
        for (final TipoPrenda t in <TipoPrenda>[
          TipoPrenda.camiseta,
          TipoPrenda.pantalon,
          TipoPrenda.falda,
          TipoPrenda.zapato,
        ])
          formaDeSilueta(t).getBounds(),
      ];
      expect(cajas.toSet(), hasLength(cajas.length));
    });

    testWidgets('el accesorio usa el icono y el resto dibuja', (tester) async {
      Widget app(TipoPrenda tipo) => MaterialApp(
        home: Scaffold(
          body: SiluetaPrenda(
            tipo: tipo,
            color: Colors.black,
            fondo: Colors.white,
            tamano: 60,
          ),
        ),
      );

      await tester.pumpWidget(app(TipoPrenda.accesorio));
      expect(find.byIcon(Icons.watch), findsOneWidget);

      await tester.pumpWidget(app(TipoPrenda.camiseta));
      expect(find.byIcon(Icons.watch), findsNothing);
      expect(
        find.descendant(
          of: find.byType(SiluetaPrenda),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
    });
  });

  group('MarcaWearHack', () {
    testWidgets('tiene el tamano de su proporcion y una etiqueta', (
      tester,
    ) async {
      final SemanticsHandle semantica = tester.ensureSemantics();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: MarcaWearHack(alto: 50))),
        ),
      );
      final Size tamano = tester.getSize(find.byType(MarcaWearHack));
      expect(tamano.height, 50);
      expect(tamano.width, closeTo(50 * MarcaWearHack.proporcion, 0.01));
      expect(find.bySemanticsLabel('WearHack'), findsOneWidget);
      semantica.dispose();
    });
  });
}
