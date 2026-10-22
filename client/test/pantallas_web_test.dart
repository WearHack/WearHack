/// Las pantallas de las issues #15 y #16 sobre el repositorio falso: closet,
/// outfits, plan semanal y elegir el mejor de N.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wearhack/app/pantalla_principal.dart';
import 'package:wearhack/features/outfits/outfit.dart';
import 'package:wearhack/mock/repositorio_falso.dart';

/// Un miercoles. El plan de ejemplo deja libres el miercoles y el domingo.
final DateTime _hoy = DateTime(2026, 10, 21);

Future<RepositorioFalso> _abrir(
  WidgetTester tester, {
  double ancho = 1200,
}) async {
  // Alto de sobra para que las hojas inferiores quepan enteras y ningun boton
  // quede fuera de la vista.
  tester.view.physicalSize = Size(ancho, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final RepositorioFalso datos = RepositorioFalso(
    hoy: _hoy,
    latencia: Duration.zero,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: PantallaPrincipal(closet: datos, outfits: datos),
    ),
  );
  await tester.pumpAndSettle();
  return datos;
}

void main() {
  group('navegacion', () {
    testWidgets('en ancho de escritorio usa un riel lateral', (
      WidgetTester tester,
    ) async {
      await _abrir(tester);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('en ancho de telefono usa la barra inferior', (
      WidgetTester tester,
    ) async {
      await _abrir(tester, ancho: 400);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });
  });

  group('closet', () {
    testWidgets('muestra todas las prendas de ejemplo', (
      WidgetTester tester,
    ) async {
      await _abrir(tester);
      expect(find.text('15 prendas'), findsOneWidget);
    });

    testWidgets('filtra por slot', (WidgetTester tester) async {
      await _abrir(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Calzado'));
      await tester.pumpAndSettle();

      expect(find.text('3 prendas'), findsOneWidget);
      expect(find.text('Tenis'), findsOneWidget);
      expect(find.text('Jean'), findsNothing);
    });

    testWidgets('eliminar una prenda la quita y descarta sus outfits', (
      WidgetTester tester,
    ) async {
      final RepositorioFalso datos = await _abrir(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Cuerpo entero'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vestido'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar del clóset'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await tester.pumpAndSettle();

      expect(find.text('Vestido'), findsNothing);
      expect(find.text('Prenda eliminada del clóset'), findsOneWidget);

      // El vestido solo estaba en el outfit o3, que el viernes tenia asignado.
      final List<Outfit> outfits = (await tester.runAsync(
        datos.outfitsDeLaSemana,
      ))!;
      expect(outfits.map((Outfit o) => o.id), isNot(contains('o3')));
    });

    testWidgets('cancelar en la confirmacion no elimina nada', (
      WidgetTester tester,
    ) async {
      await _abrir(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Cuerpo entero'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vestido'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar del clóset'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.text('Vestido'), findsOneWidget);
    });
  });

  group('outfits', () {
    testWidgets('lista los outfits de la semana', (WidgetTester tester) async {
      await _abrir(tester);

      await tester.tap(find.text('Outfits'));
      await tester.pumpAndSettle();

      expect(find.text('Camiseta · Jean · Tenis'), findsOneWidget);
      expect(find.text('Vestido · Tenis'), findsOneWidget);
    });
  });

  group('semana', () {
    testWidgets('pinta los siete dias con sus dos dias libres', (
      WidgetTester tester,
    ) async {
      await _abrir(tester);

      await tester.tap(find.text('Semana'));
      await tester.pumpAndSettle();

      expect(find.text('Semana del 19 oct al 25 oct'), findsOneWidget);
      for (final String dia in <String>['Lunes', 'Miércoles', 'Domingo']) {
        expect(find.text(dia), findsOneWidget);
      }
      expect(find.textContaining('Sin outfit'), findsNWidgets(2));
    });

    testWidgets('dejar un dia libre lo vacia', (WidgetTester tester) async {
      await _abrir(tester);
      await tester.tap(find.text('Semana'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lunes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dejar el día libre'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Sin outfit'), findsNWidgets(3));
    });

    testWidgets('asignar un outfit a un dia libre lo llena', (
      WidgetTester tester,
    ) async {
      await _abrir(tester);
      await tester.tap(find.text('Semana'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Miércoles'));
      await tester.pumpAndSettle();
      // Un dia libre no ofrece dejarse libre.
      expect(find.text('Dejar el día libre'), findsNothing);
      await tester.tap(find.text('Vestido · Tenis'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Sin outfit'), findsOneWidget);
    });
  });

  group('elegir el mejor de N', () {
    Future<void> irAElegir(WidgetTester tester) async {
      await tester.tap(find.text('Outfits'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Elegir'));
      await tester.pumpAndSettle();
    }

    FilledButton botonUsar(WidgetTester tester) => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Usar este outfit'),
    );

    testWidgets('muestra las tres opciones y no deja confirmar sin marcar', (
      WidgetTester tester,
    ) async {
      await _abrir(tester);
      await irAElegir(tester);

      expect(find.text('Elige tu outfit de hoy'), findsOneWidget);
      expect(find.text('Camiseta · Jean · Tenis'), findsOneWidget);
      expect(find.text('Vestido · Tenis'), findsOneWidget);
      expect(find.text('Blusa · Falda · Zapatos'), findsOneWidget);
      expect(botonUsar(tester).onPressed, isNull);
    });

    testWidgets('marcar no registra nada hasta confirmar', (
      WidgetTester tester,
    ) async {
      final RepositorioFalso datos = await _abrir(tester);
      await irAElegir(tester);

      await tester.tap(find.text('Vestido · Tenis'));
      await tester.pump();
      expect(botonUsar(tester).onPressed, isNotNull);

      final LoteOpciones lote = (await tester.runAsync(datos.opcionesDeHoy))!;
      expect(lote.elegidoId, isNull);
    });

    testWidgets('confirmar registra la eleccion y la pone como outfit de hoy', (
      WidgetTester tester,
    ) async {
      await _abrir(tester);
      await irAElegir(tester);

      await tester.tap(find.text('Vestido · Tenis'));
      await tester.pump();
      await tester.tap(find.text('Usar este outfit'));
      await tester.pumpAndSettle();

      expect(find.text('Listo, ese es tu outfit de hoy'), findsOneWidget);
      expect(find.text('Ya elegiste el outfit de hoy.'), findsOneWidget);
      // Ya no se puede volver a elegir: un lote da una sola seleccion.
      expect(find.widgetWithText(FilledButton, 'Elegir'), findsNothing);

      // El miercoles estaba libre; ahora solo queda el domingo.
      await tester.tap(find.text('Semana'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sin outfit'), findsOneWidget);
    });
  });

  group('repositorio falso', () {
    test('un lote no admite una segunda eleccion', () async {
      final RepositorioFalso datos = RepositorioFalso(
        hoy: _hoy,
        latencia: Duration.zero,
      );
      final LoteOpciones lote = await datos.opcionesDeHoy();

      await datos.elegir(lote.id, 'o1');

      expect(datos.elegir(lote.id, 'o3'), throwsStateError);
    });

    test('no se puede elegir un outfit que no esta en el lote', () async {
      final RepositorioFalso datos = RepositorioFalso(
        hoy: _hoy,
        latencia: Duration.zero,
      );
      final LoteOpciones lote = await datos.opcionesDeHoy();

      expect(datos.elegir(lote.id, 'o2'), throwsArgumentError);
    });
  });
}
