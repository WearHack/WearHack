/// Las pantallas de las issues #15 a #18 sobre el repositorio falso: closet,
/// outfits, plan semanal, elegir el mejor de N, el contexto de hoy y las
/// marcas aliadas.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wearhack/app/pantalla_principal.dart';
import 'package:wearhack/core/ui/formato.dart';
import 'package:wearhack/core/vocabulario.dart';
import 'package:wearhack/features/outfits/contexto.dart';
import 'package:wearhack/features/outfits/outfit.dart';
import 'package:wearhack/features/outfits/repositorio_clima.dart';
import 'package:wearhack/features/publicidad/catalogo.dart';
import 'package:wearhack/mock/repositorio_falso.dart';
import 'package:wearhack/platform/ubicacion.dart';

/// Un miercoles. El plan de ejemplo deja libres el miercoles y el domingo.
final DateTime _hoy = DateTime(2026, 10, 21);

/// Una ubicacion que responde lo que se le diga, sin navegador.
class _UbicacionFalsa implements ServicioUbicacion {
  _UbicacionFalsa(this.resultado, {this.disponible = true});

  final ResultadoUbicacion resultado;

  @override
  final bool disponible;

  @override
  Future<ResultadoUbicacion> obtener() async => resultado;
}

/// Un clima que anota desde donde se lo pidieron.
class _ClimaQueAnota implements RepositorioClima {
  _ClimaQueAnota(this.temperatura);

  final double? temperatura;
  double? latitud;
  double? longitud;

  @override
  Future<double?> temperaturaEn({
    required double latitud,
    required double longitud,
  }) async {
    this.latitud = latitud;
    this.longitud = longitud;
    return temperatura;
  }
}

/// Bogota, con mas decimales de los que deberian salir del dispositivo.
const UbicacionObtenida _bogota = UbicacionObtenida(
  latitud: 4.711234,
  longitud: -74.072156,
);

Future<RepositorioFalso> _abrir(
  WidgetTester tester, {
  double ancho = 1200,
  ServicioUbicacion? ubicacion,
  RepositorioClima? clima,
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
      home: PantallaPrincipal(
        closet: datos,
        outfits: datos,
        clima: clima ?? datos,
        ubicacion: ubicacion ?? _UbicacionFalsa(_bogota),
        publicidad: datos,
      ),
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

      final LoteOpciones lote = (await tester.runAsync(
        () => datos.opcionesDeHoy(const ContextoOutfit()),
      ))!;
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
    test(
      'un dia no admite una segunda eleccion, ni con otro contexto',
      () async {
        final RepositorioFalso datos = RepositorioFalso(
          hoy: _hoy,
          latencia: Duration.zero,
        );
        final LoteOpciones lote = await datos.opcionesDeHoy(
          const ContextoOutfit(),
        );
        await datos.elegir(lote.id, 'o1');

        final LoteOpciones otro = await datos.opcionesDeHoy(
          const ContextoOutfit(ocasion: Ocasion.oficina),
        );
        expect(otro.elegidoId, 'o1');
        expect(datos.elegir(otro.id, 'o2'), throwsStateError);
      },
    );

    test(
      'las opciones respetan la formalidad de la ocasion y el clima',
      () async {
        final RepositorioFalso datos = RepositorioFalso(
          hoy: _hoy,
          latencia: Duration.zero,
        );
        final LoteOpciones lote = await datos.opcionesDeHoy(
          const ContextoOutfit(ocasion: Ocasion.oficina, clima: Clima.templado),
        );

        expect(lote.opciones.map((Outfit o) => o.id), <String>['o2']);
      },
    );

    test('no se puede elegir un outfit que no esta en el lote', () async {
      final RepositorioFalso datos = RepositorioFalso(
        hoy: _hoy,
        latencia: Duration.zero,
      );
      final LoteOpciones lote = await datos.opcionesDeHoy(
        const ContextoOutfit(),
      );

      expect(datos.elegir(lote.id, 'o2'), throwsArgumentError);
    });
  });

  group('contexto de hoy', () {
    Future<void> irAOutfits(WidgetTester tester) async {
      await tester.tap(find.text('Outfits'));
      await tester.pumpAndSettle();
    }

    ChoiceChip chip(WidgetTester tester, String texto) =>
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, texto));

    testWidgets('arranca en dia a dia, sin mood y sin clima', (
      WidgetTester tester,
    ) async {
      await _abrir(tester);
      await irAOutfits(tester);

      expect(chip(tester, 'Día a día').selected, isTrue);
      for (final Mood m in Mood.values) {
        expect(chip(tester, m.etiqueta).selected, isFalse);
      }
      expect(find.text('Usar mi ubicación'), findsOneWidget);
      expect(
        find.text('Elige entre 3 opciones pensadas para ti.'),
        findsOneWidget,
      );
    });

    testWidgets('cambiar la ocasion cambia las opciones', (
      WidgetTester tester,
    ) async {
      await _abrir(tester);
      await irAOutfits(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Oficina'));
      await tester.pumpAndSettle();
      expect(
        find.text('Elige entre 2 opciones pensadas para ti.'),
        findsOneWidget,
      );

      // Ningun outfit de ejemplo es formal.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Formal'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No hay suficientes outfits'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Elegir'), findsNothing);
    });

    testWidgets('el mood se marca y se desmarca', (WidgetTester tester) async {
      await _abrir(tester);
      await irAOutfits(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Relajado'));
      await tester.pumpAndSettle();
      expect(chip(tester, 'Relajado').selected, isTrue);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Relajado'));
      await tester.pumpAndSettle();
      expect(chip(tester, 'Relajado').selected, isFalse);
    });

    testWidgets('con permiso usa el clima de la zona', (
      WidgetTester tester,
    ) async {
      await _abrir(tester);
      await irAOutfits(tester);

      await tester.tap(find.text('Usar mi ubicación'));
      await tester.pumpAndSettle();

      // 18 grados es templado: de dia a dia solo quedan o1 y o2.
      expect(find.text('Templado · 18 °C en tu zona'), findsOneWidget);
      expect(
        find.text('Elige entre 2 opciones pensadas para ti.'),
        findsOneWidget,
      );
      expect(find.text('Actualizar'), findsOneWidget);
    });

    testWidgets('la posicion sale redondeada a dos decimales', (
      WidgetTester tester,
    ) async {
      final _ClimaQueAnota clima = _ClimaQueAnota(30);
      await _abrir(tester, clima: clima);
      await irAOutfits(tester);

      await tester.tap(find.text('Usar mi ubicación'));
      await tester.pumpAndSettle();

      expect(clima.latitud, 4.71);
      expect(clima.longitud, -74.07);
      expect(find.text('Cálido · 30 °C en tu zona'), findsOneWidget);
    });

    testWidgets('sin permiso genera sin clima', (WidgetTester tester) async {
      await _abrir(
        tester,
        ubicacion: _UbicacionFalsa(const UbicacionDenegada()),
      );
      await irAOutfits(tester);

      await tester.tap(find.text('Usar mi ubicación'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No diste permiso de ubicación'),
        findsOneWidget,
      );
      expect(
        find.text('Elige entre 3 opciones pensadas para ti.'),
        findsOneWidget,
      );
    });

    testWidgets('si el clima no responde, genera sin clima', (
      WidgetTester tester,
    ) async {
      await _abrir(tester, clima: _ClimaQueAnota(null));
      await irAOutfits(tester);

      await tester.tap(find.text('Usar mi ubicación'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No se pudo obtener el clima'),
        findsOneWidget,
      );
      expect(
        find.text('Elige entre 3 opciones pensadas para ti.'),
        findsOneWidget,
      );
    });

    testWidgets('sin ubicacion en el dispositivo ni se ofrece', (
      WidgetTester tester,
    ) async {
      await _abrir(
        tester,
        ubicacion: _UbicacionFalsa(
          const UbicacionNoDisponible(),
          disponible: false,
        ),
      );
      await irAOutfits(tester);

      expect(
        find.textContaining('no permite usar tu ubicación'),
        findsOneWidget,
      );
      expect(find.text('Usar mi ubicación'), findsNothing);
    });
  });

  group('bandas de clima', () {
    test('frio por debajo de 14, calido por encima de 22', () {
      expect(climaPara(13.9), Clima.frio);
      expect(climaPara(14), Clima.templado);
      expect(climaPara(22), Clima.templado);
      expect(climaPara(22.1), Clima.calido);
    });
  });

  group('marcas aliadas', () {
    Future<void> irAMarcas(WidgetTester tester) async {
      await tester.tap(find.text('Marcas'));
      await tester.pumpAndSettle();
    }

    testWidgets('la navegacion tiene cuatro secciones', (
      WidgetTester tester,
    ) async {
      await _abrir(tester);
      expect(
        tester.widget<NavigationRail>(find.byType(NavigationRail)).destinations,
        hasLength(4),
      );
    });

    testWidgets('muestra el ranking en orden y sin las de menos de 5', (
      WidgetTester tester,
    ) async {
      await _abrir(tester);
      await irAMarcas(tester);

      expect(find.text('Prendas puente para ti'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('#4'), findsOneWidget);
      expect(find.text('#5'), findsNothing);
      expect(find.text('Abre 9 combinaciones'), findsOneWidget);
      expect(find.text('Nuevo para ti: Formal'), findsOneWidget);
      // Los mocasines solo abren 3: no llegan al umbral.
      expect(find.text('Mocasines negros'), findsNothing);
    });

    testWidgets('en un telefono estrecho nada se desborda', (
      WidgetTester tester,
    ) async {
      // Un desborde es un error en los tests: si algo no cupiera, esto falla.
      await _abrir(tester, ancho: 360);
      await irAMarcas(tester);
      await tester.tap(find.text('Blazer negro de paño'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Norte Urbano'));
      await tester.pumpAndSettle();

      expect(find.text('Camisa blanca Oxford'), findsOneWidget);
    });

    testWidgets('el detalle explica que combinaciones abre', (
      WidgetTester tester,
    ) async {
      await _abrir(tester);
      await irAMarcas(tester);

      await tester.tap(find.text('Blazer negro de paño'));
      await tester.pumpAndSettle();

      expect(
        find.text('Abre 9 combinaciones nuevas con lo que ya tienes'),
        findsOneWidget,
      );
      expect(find.widgetWithText(Chip, 'Formal'), findsOneWidget);
      expect(
        find.text('Camisa · Pantalón · Chaqueta · Zapatos'),
        findsOneWidget,
      );
      expect(find.textContaining('marca aliada'), findsOneWidget);
    });

    testWidgets('el catalogo de una marca marca sus prendas puente', (
      WidgetTester tester,
    ) async {
      await _abrir(tester);
      await irAMarcas(tester);

      await tester.tap(find.text('Casa Lino'));
      await tester.pumpAndSettle();

      expect(find.text('Pantalón de lino beige'), findsOneWidget);
      expect(find.text('Vestido camisero verde'), findsOneWidget);
      expect(find.text('Sandalias de cuero'), findsOneWidget);
      expect(find.text('Prenda puente'), findsOneWidget);
      expect(find.text('\$ 159.900'), findsOneWidget);

      await tester.tap(find.text('Pantalón de lino beige'));
      await tester.pumpAndSettle();
      expect(
        find.text('Abre 7 combinaciones nuevas con lo que ya tienes'),
        findsOneWidget,
      );
    });
  });

  group('repositorio falso: prendas puente', () {
    test('vienen ordenadas y todas llegan al umbral', () async {
      final RepositorioFalso datos = RepositorioFalso(
        hoy: _hoy,
        latencia: Duration.zero,
      );
      final List<int> combinaciones = <int>[
        for (final PrendaPuente p in await datos.prendasPuente())
          p.combinacionesBuenas,
      ];

      expect(combinaciones, <int>[9, 7, 7, 5]);
    });

    test('las combinaciones de ejemplo no usan prendas eliminadas', () async {
      final RepositorioFalso datos = RepositorioFalso(
        hoy: _hoy,
        latencia: Duration.zero,
      );
      // El pantalon negro esta en dos de las tres del blazer.
      await datos.eliminarPrenda('p06');

      final PrendaPuente blazer = (await datos.prendasPuente()).first;
      expect(blazer.ejemplos.map((Outfit o) => o.id), <String>['pp-c01-3']);
    });
  });

  group('formato de precios', () {
    test('separa los miles con punto', () {
      expect(formatoPesos(900), '\$ 900');
      expect(formatoPesos(49900), '\$ 49.900');
      expect(formatoPesos(289900), '\$ 289.900');
      expect(formatoPesos(1000000), '\$ 1.000.000');
    });
  });
}
