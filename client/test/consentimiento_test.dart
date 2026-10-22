/// La autorizacion de la colorimetria (issue #14): la forma que exige la
/// politica de datos y que el texto no cambie sin subir de version.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wearhack/core/ui/formato.dart';
import 'package:wearhack/features/colorimetria/consentimiento.dart';
import 'package:wearhack/features/colorimetria/ui/pantalla_colorimetria.dart';
import 'package:wearhack/features/colorimetria/ui/pantalla_consentimiento.dart';
import 'package:wearhack/features/colorimetria/ui/texto_consentimiento.dart';
import 'package:wearhack/mock/repositorio_falso.dart';

/// La huella de cada version del texto. Al cambiar el texto se sube
/// `versionTextoConsentimiento` y se anade aqui la huella nueva.
const Map<int, String> _huellas = <int, String>{
  1: '35cd0ae00b6da75f1171bc3e986edb262af899eecddf3a1d2255f2d79c54c23e',
};

Future<RepositorioFalso> _abrir(
  WidgetTester tester, {
  Consentimiento? consentimiento,
  bool capturaDisponible = false,
}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final RepositorioFalso datos = RepositorioFalso(
    latencia: Duration.zero,
    consentimiento: consentimiento,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: PantallaColorimetria(
        repositorio: datos,
        capturaDisponible: capturaDisponible,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return datos;
}

Future<void> _irAlConsentimiento(WidgetTester tester) async {
  await tester.tap(find.text('Calcular mi temporada'));
  await tester.pumpAndSettle();
}

void main() {
  group('texto', () {
    test('cambiar el texto obliga a subir la version', () {
      final String huella = sha256
          .convert(utf8.encode(textoCompletoConsentimiento()))
          .toString();
      expect(
        huella,
        _huellas[versionTextoConsentimiento],
        reason:
            'el texto del consentimiento cambio: sube '
            'versionTextoConsentimiento y anade su huella a _huellas',
      );
    });

    test('incluye el contenido minimo de la politica', () {
      final String texto = textoCompletoConsentimiento();
      for (final String obligatorio in <String>[
        'recorte de tu rostro',
        'temporada de color',
        'sensibles',
        'voluntario',
        'no se guarda',
        'Quién accede',
        'Estados Unidos',
        'revocar',
        'Política de tratamiento de información',
      ]) {
        expect(texto, contains(obligatorio));
      }
    });
  });

  group('pantalla de autorizacion', () {
    testWidgets('no tiene casillas y ofrece omitir junto a autorizar', (
      WidgetTester tester,
    ) async {
      await _abrir(tester);
      await _irAlConsentimiento(tester);

      expect(find.byType(PantallaConsentimiento), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Autorizo'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Omitir'), findsOneWidget);

      // Del mismo ancho: omitir no puede quedar escondido.
      expect(
        tester.getSize(find.widgetWithText(OutlinedButton, 'Omitir')).width,
        tester.getSize(find.widgetWithText(FilledButton, 'Autorizo')).width,
      );
    });

    testWidgets('autorizar registra la version vigente', (
      WidgetTester tester,
    ) async {
      final RepositorioFalso datos = await _abrir(tester);
      await _irAlConsentimiento(tester);

      await tester.tap(find.text('Autorizo'));
      await tester.pumpAndSettle();

      expect(find.text('Autorizaste el análisis'), findsOneWidget);
      final Consentimiento c = (await tester.runAsync<Consentimiento?>(
        datos.consentimientoColorimetria,
      ))!;
      expect(c.decision, DecisionConsentimiento.autorizo);
      expect(c.version, versionTextoConsentimiento);
    });

    testWidgets('omitir no autoriza y se puede volver a intentar', (
      WidgetTester tester,
    ) async {
      final RepositorioFalso datos = await _abrir(tester);
      await _irAlConsentimiento(tester);

      await tester.tap(find.text('Omitir'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Omitiste este paso'), findsOneWidget);
      expect(find.text('Calcular mi temporada'), findsOneWidget);
      final Consentimiento c = (await tester.runAsync<Consentimiento?>(
        datos.consentimientoColorimetria,
      ))!;
      expect(c.vigente, isFalse);
    });

    testWidgets('salir con la flecha de atras no registra nada', (
      WidgetTester tester,
    ) async {
      final RepositorioFalso datos = await _abrir(tester);
      await _irAlConsentimiento(tester);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(await tester.runAsync(datos.consentimientoColorimetria), isNull);
    });
  });

  group('estado de la autorizacion', () {
    testWidgets('una autorizacion sobre un texto viejo pide revisarlo', (
      WidgetTester tester,
    ) async {
      await _abrir(
        tester,
        consentimiento: Consentimiento(
          decision: DecisionConsentimiento.autorizo,
          version: versionTextoConsentimiento - 1,
          fecha: DateTime(2026, 9, 1),
        ),
      );

      expect(
        find.textContaining('El texto de la autorización cambió'),
        findsOneWidget,
      );
      expect(find.text('Revisar la autorización'), findsOneWidget);
      expect(find.text('Autorizaste el análisis'), findsNothing);
    });

    testWidgets('en web dice que la foto se toma desde el movil', (
      WidgetTester tester,
    ) async {
      await _abrir(tester, consentimiento: _vigente());

      expect(find.textContaining('desde la app móvil'), findsOneWidget);
      expect(find.textContaining('Tomar la foto'), findsNothing);
    });

    testWidgets('en el movil ofrece la foto', (WidgetTester tester) async {
      await _abrir(tester, consentimiento: _vigente(), capturaDisponible: true);

      expect(find.textContaining('Tomar la foto'), findsOneWidget);
    });

    testWidgets('revocar vuelve al principio', (WidgetTester tester) async {
      final RepositorioFalso datos = await _abrir(
        tester,
        consentimiento: _vigente(),
      );

      await tester.tap(find.text('Revocar autorización'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Revocar'));
      await tester.pumpAndSettle();

      expect(find.text('Autorización revocada'), findsOneWidget);
      expect(find.text('Calcular mi temporada'), findsOneWidget);
      expect(await tester.runAsync(datos.consentimientoColorimetria), isNull);
    });
  });

  test('formato de fecha larga', () {
    expect(formatoFecha(DateTime(2026, 10, 22)), '22 de octubre de 2026');
    expect(formatoFecha(DateTime(2027, 1, 5)), '5 de enero de 2027');
  });
}

Consentimiento _vigente() => Consentimiento(
  decision: DecisionConsentimiento.autorizo,
  version: versionTextoConsentimiento,
  fecha: DateTime(2026, 10, 22),
);
