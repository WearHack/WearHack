import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wearhack/core/ui/movimiento.dart';

Widget _app(Widget hijo, {bool reducir = false}) => MaterialApp(
  home: Builder(
    builder: (BuildContext context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reducir),
      child: Scaffold(body: hijo),
    ),
  ),
);

double _opacidad(WidgetTester tester) => tester
    .widget<Opacity>(
      find.descendant(of: find.byType(Aparece), matching: find.byType(Opacity)),
    )
    .opacity;

void main() {
  group('Aparece', () {
    testWidgets('entra desde transparente y termina visible', (tester) async {
      await tester.pumpWidget(_app(const Aparece(child: Text('hola'))));
      expect(_opacidad(tester), 0);

      await tester.pump(const Duration(milliseconds: 150));
      expect(_opacidad(tester), inInclusiveRange(0.01, 0.99));

      await tester.pumpAndSettle();
      expect(_opacidad(tester), 1);
      expect(find.text('hola'), findsOneWidget);
    });

    testWidgets('con reducir animaciones aparece de una', (tester) async {
      await tester.pumpWidget(
        _app(const Aparece(child: Text('hola')), reducir: true),
      );
      expect(_opacidad(tester), 1);
    });

    testWidgets('animar en falso lo deja ya puesto', (tester) async {
      await tester.pumpWidget(
        _app(const Aparece(animar: false, child: Text('hola'))),
      );
      expect(_opacidad(tester), 1);
    });

    testWidgets('un indice alto espera mas que el primero', (tester) async {
      await tester.pumpWidget(
        _app(
          const Column(
            children: <Widget>[
              Aparece(indice: 0, child: Text('uno')),
              Aparece(indice: 6, child: Text('siete')),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final List<double> valores = tester
          .widgetList<Opacity>(
            find.descendant(
              of: find.byType(Column),
              matching: find.byType(Opacity),
            ),
          )
          .map((Opacity o) => o.opacity)
          .toList();
      expect(valores[0], greaterThan(valores[1]));
      await tester.pumpAndSettle();
    });

    testWidgets('el desliz mueve el contenido hacia abajo al empezar', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const Center(child: Aparece(desliz: 20, child: Text('hola')))),
      );
      final double inicio = tester.getTopLeft(find.text('hola')).dy;
      await tester.pumpAndSettle();
      final double fin = tester.getTopLeft(find.text('hola')).dy;
      expect(inicio - fin, closeTo(20, 0.5));
    });
  });

  group('EsqueletoCuadricula', () {
    testWidgets('dibuja las cajas pedidas', (tester) async {
      // Con reducir animaciones el pulso queda quieto y la prueba termina.
      await tester.pumpWidget(
        _app(const EsqueletoCuadricula(cantidad: 4), reducir: true),
      );
      expect(
        find.descendant(
          of: find.byType(EsqueletoCuadricula),
          matching: find.byType(DecoratedBox),
        ),
        findsNWidgets(4),
      );
    });
  });
}
