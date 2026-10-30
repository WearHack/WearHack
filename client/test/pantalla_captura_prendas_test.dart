/// La pantalla de captura de prendas (issue #11), con camara, cola y sensor
/// falsos. La camara trasera y el sensor termico reales solo se prueban en un
/// telefono.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wearhack/app/pantalla_principal.dart';
import 'package:wearhack/features/closet/captura/captura_de_prendas.dart';
import 'package:wearhack/features/closet/captura/cola_captura.dart';
import 'package:wearhack/features/closet/captura/item_cola.dart';
import 'package:wearhack/features/closet/captura/subidor_pendiente.dart';
import 'package:wearhack/features/closet/ui/pantalla_captura_prendas.dart';
import 'package:wearhack/mock/repositorio_falso.dart';
import 'package:wearhack/platform/captura/camara.dart';
import 'package:wearhack/platform/ubicacion.dart';

import 'helpers/captura_ui_helpers.dart';
import 'helpers/cola_helpers.dart';

/// Una cola parada: lo que se encola se queda donde esta, para poder mirarlo.
Future<ColaCaptura> _colaQuieta({
  ConfiguracionCola configuracion = const ConfiguracionCola(),
  ProcesadorFalso? procesador,
}) async {
  int siguiente = 0;
  final ColaCaptura cola = await ColaCaptura.abrir(
    almacen: AlmacenEnMemoria(),
    procesador: procesador ?? ProcesadorFalso(),
    subidor: SubidorFalso(),
    configuracion: configuracion,
    automatica: false,
    generarId: () => 'f${siguiente++}',
  );
  return cola;
}

Future<void> _abrir(
  WidgetTester tester, {
  required ColaCaptura cola,
  CamaraFalsa? camara,
  TermicoFalso? termico,
}) async {
  // La pantalla arranca la cola; parada, no avanza sola durante la prueba.
  await cola.detener();
  await tester.pumpWidget(
    MaterialApp(
      home: PantallaCapturaPrendas(
        cola: cola,
        crearCamara: () => camara ?? CamaraFalsa(),
        termico: termico ?? TermicoFalso(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _texto(WidgetTester tester, String clave) => tester
    .widget<Text>(
      find.descendant(of: find.byKey(Key(clave)), matching: find.byType(Text)),
    )
    .data!;

void main() {
  testWidgets('disparar encola la foto y la cuenta como por procesar', (
    WidgetTester tester,
  ) async {
    final ColaCaptura cola = await _colaQuieta();
    final CamaraFalsa camara = CamaraFalsa();
    await _abrir(tester, cola: cola, camara: camara);

    expect(find.byKey(const Key('vista_previa')), findsOneWidget);
    await tester.tap(find.byKey(const Key('disparar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('disparar')));
    await tester.pumpAndSettle();

    expect(camara.fotosTomadas, 2);
    expect(cola.items, hasLength(2));
    expect(_texto(tester, 'por_procesar'), 'Por procesar: 2');
  });

  testWidgets('con la cola llena avisa y no encola', (
    WidgetTester tester,
  ) async {
    final ColaCaptura cola = await _colaQuieta(
      configuracion: const ConfiguracionCola(maxPendientes: 1),
    );
    await _abrir(tester, cola: cola);

    await tester.tap(find.byKey(const Key('disparar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('disparar')));
    await tester.pumpAndSettle();

    expect(cola.items, hasLength(1));
    expect(find.textContaining('Hay 1 fotos esperando'), findsOneWidget);
  });

  testWidgets('el aviso de calor sigue al sensor', (WidgetTester tester) async {
    final TermicoFalso termico = TermicoFalso(caliente: true);
    await _abrir(tester, cola: await _colaQuieta(), termico: termico);
    expect(find.byKey(const Key('aviso_calor')), findsOneWidget);

    termico.caliente = false;
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const Key('aviso_calor')), findsNothing);
  });

  testWidgets('sin camara trasera lo dice y no deja disparar', (
    WidgetTester tester,
  ) async {
    await _abrir(
      tester,
      cola: await _colaQuieta(),
      camara: CamaraFalsa(falloAlAbrir: const SinCamaraTrasera()),
    );

    expect(find.textContaining('no tiene cámara trasera'), findsOneWidget);
    final FloatingActionButton boton = tester.widget(
      find.byKey(const Key('disparar')),
    );
    expect(boton.onPressed, isNull);
  });

  group('fallidas', () {
    /// Una cola con dos fotos que ya agotaron su unico intento.
    Future<ColaCaptura> conFallidas() async {
      final ProcesadorFalso procesador = ProcesadorFalso()
        ..fallanLasQueEmpiezanPor.add(9);
      final ColaCaptura cola = await _colaQuieta(
        procesador: procesador,
        configuracion: const ConfiguracionCola(maxIntentos: 1),
      );
      await cola.encolar(Uint8List.fromList(<int>[9, 1]));
      await cola.encolar(Uint8List.fromList(<int>[9, 2]));
      await cola.ronda();
      expect(
        cola.items.map((ItemCola i) => i.estado),
        everyElement(EstadoItem.fallida),
      );
      return cola;
    }

    testWidgets('se pueden descartar de una en una', (
      WidgetTester tester,
    ) async {
      final ColaCaptura cola = await conFallidas();
      await _abrir(tester, cola: cola);
      expect(_texto(tester, 'fallidas'), 'Fallidas: 2');

      await tester.tap(find.byKey(const Key('fallidas')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('descartar_f0')));
      await tester.pumpAndSettle();

      expect(cola.items.map((ItemCola i) => i.id), <String>['f1']);
      expect(_texto(tester, 'fallidas'), 'Fallidas: 1');
    });

    testWidgets('reintentar las devuelve a por procesar', (
      WidgetTester tester,
    ) async {
      final ColaCaptura cola = await conFallidas();
      await _abrir(tester, cola: cola);

      await tester.tap(find.byKey(const Key('fallidas')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reintentar_fallidas')));
      await tester.pumpAndSettle();

      expect(
        cola.items.map((ItemCola i) => i.estado),
        everyElement(EstadoItem.porProcesar),
      );
      expect(_texto(tester, 'por_procesar'), 'Por procesar: 2');
    });
  });

  group('entrada desde el closet', () {
    Future<void> principal(
      WidgetTester tester, {
      CapturaDePrendas? captura,
    }) async {
      final RepositorioFalso datos = RepositorioFalso(latencia: Duration.zero);
      await tester.pumpWidget(
        MaterialApp(
          home: PantallaPrincipal(
            closet: datos,
            outfits: datos,
            clima: datos,
            ubicacion: _SinUbicacion(),
            publicidad: datos,
            consentimiento: datos,
            capturaRostroDisponible: false,
            capturaPrendas: captura,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('sin captura no hay boton', (WidgetTester tester) async {
      await principal(tester);
      expect(find.byKey(const Key('agregar_prendas')), findsNothing);
    });

    testWidgets('con captura, el boton abre la pantalla', (
      WidgetTester tester,
    ) async {
      final ColaCaptura cola = await _colaQuieta();
      await cola.detener();
      await principal(
        tester,
        captura: CapturaDePrendas(
          cola: cola,
          termico: TermicoFalso(),
          crearCamara: CamaraFalsa.new,
        ),
      );

      await tester.tap(find.byKey(const Key('agregar_prendas')));
      await tester.pumpAndSettle();
      expect(find.byType(PantallaCapturaPrendas), findsOneWidget);
    });
  });

  test('sin Closet que reciba, subir es como no tener red', () async {
    await expectLater(
      const SubidorPendiente().subir('f0', prendaDeEjemplo()),
      throwsA(isA<SinConexion>()),
    );
  });
}

class _SinUbicacion implements ServicioUbicacion {
  @override
  bool get disponible => false;

  @override
  Future<ResultadoUbicacion> obtener() async => const UbicacionNoDisponible();
}
