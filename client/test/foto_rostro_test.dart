/// La foto del rostro de la colorimetria (issue #14): que no se abra la camara
/// sin consentimiento, que la foto completa solo la vea el recortador, y que el
/// recorte no se persista.
///
/// Se prueba con una camara y un recortador falsos, sin telefono. Lo que no se
/// puede probar aqui (la camara real, ML Kit sobre un rostro de verdad) esta en
/// la lista de pruebas en un telefono.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wearhack/core/color/perfil_icc.dart';
import 'package:wearhack/core/recorte/configuracion_recorte.dart';
import 'package:wearhack/core/recorte/controles_calidad.dart';
import 'package:wearhack/features/colorimetria/consentimiento.dart';
import 'package:wearhack/features/colorimetria/ui/pantalla_colorimetria.dart';
import 'package:wearhack/features/colorimetria/ui/pantalla_foto_rostro.dart';
import 'package:wearhack/mock/repositorio_falso.dart';
import 'package:wearhack/platform/captura/camara.dart';
import 'package:wearhack/platform/captura/contratos.dart';

class _CamaraFalsa implements CamaraDeCaptura {
  _CamaraFalsa({this.falla});

  /// Lo que lanza `inicializar`, si algo.
  final Object? falla;

  int inicializada = 0;
  int liberada = 0;
  int fotos = 0;

  static final Uint8List bytesDeLaFoto = Uint8List.fromList(<int>[1, 2, 3, 4]);

  @override
  Future<void> inicializar() async {
    inicializada++;
    final Object? f = falla;
    if (f != null) throw f;
  }

  @override
  Widget vistaPrevia() => const ColoredBox(color: Colors.black);

  @override
  bool get guiaDeDistanciaActiva => false;

  @override
  Stream<int?> get anchoDelRostroEnVivo => const Stream<int?>.empty();

  @override
  Future<FotoTomada> tomarFoto() async {
    fotos++;
    return FotoTomada(bytes: bytesDeLaFoto, extension: 'jpg');
  }

  @override
  Future<void> liberar() async {
    liberada++;
  }
}

class _RecortadorFalso implements FaceCropper {
  _RecortadorFalso({this.resultado, this.error});

  final RecorteFacial? resultado;
  final Object? error;

  /// Lo que recibio cada llamada: la unica puerta por la que pasa la foto.
  final List<Uint8List> recibidos = <Uint8List>[];

  @override
  bool get disponible => true;

  @override
  Future<RecorteFacial?> recortar(Uint8List foto) async {
    recibidos.add(foto);
    final Object? e = error;
    if (e != null) throw e;
    return resultado;
  }
}

RecorteFacial _recorte({
  List<ControlCalidad> fallidos = const <ControlCalidad>[],
  bool variosRostros = false,
}) => RecorteFacial(
  png: Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2))),
  ancho: 2,
  alto: 2,
  caja: const CajaRostro(left: 0, top: 0, width: 2, height: 2),
  margenSuperiorPx: 0,
  perfilOrigen: 'sRGB',
  perfilOrigenSupuesto: false,
  variosRostros: variosRostros,
  controles: ControlesCalidad(
    anchoRostroPx: 2,
    porcentajeQuemados: 0,
    porcentajeNegros: 0,
    nitidez: 1,
    fallidos: fallidos,
  ),
);

Consentimiento _autorizo({int? version}) => Consentimiento(
  decision: DecisionConsentimiento.autorizo,
  version: version ?? versionTextoConsentimiento,
  fecha: DateTime(2026, 10, 22),
);

/// Lo que devolvio la pantalla al cerrarse.
class _Resultado {
  RecorteFacial? recorte;
  bool cerro = false;
}

/// Abre la pantalla desde un boton, como lo hace la app, para poder ver que
/// devuelve al cerrarse.
Future<_Resultado> _abrir(
  WidgetTester tester, {
  Consentimiento? consentimiento,
  required _CamaraFalsa camara,
  required _RecortadorFalso recortador,
  List<int>? llamadasACrearCamara,
}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final RepositorioFalso datos = RepositorioFalso(
    latencia: Duration.zero,
    consentimiento: consentimiento,
  );
  final _Resultado resultado = _Resultado();

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                resultado.recorte = await Navigator.of(context)
                    .push<RecorteFacial>(
                      MaterialPageRoute<RecorteFacial>(
                        builder: (_) => PantallaFotoRostro(
                          repositorio: datos,
                          crearCamara: () {
                            llamadasACrearCamara?.add(1);
                            return camara;
                          },
                          recortador: recortador,
                        ),
                      ),
                    );
                resultado.cerro = true;
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return resultado;
}

void main() {
  group('consentimiento antes de la camara', () {
    for (final (String nombre, Consentimiento? c)
        in <(String, Consentimiento?)>[
          ('nunca decidio', null),
          (
            'omitio',
            Consentimiento(
              decision: DecisionConsentimiento.omitio,
              version: versionTextoConsentimiento,
              fecha: DateTime(2026, 10, 22),
            ),
          ),
          ('autorizo un texto que ya cambio', _autorizo(version: 0)),
        ]) {
      testWidgets('si $nombre, no se crea ni se abre la camara', (
        WidgetTester tester,
      ) async {
        final _CamaraFalsa camara = _CamaraFalsa();
        final List<int> creadas = <int>[];
        await _abrir(
          tester,
          consentimiento: c,
          camara: camara,
          recortador: _RecortadorFalso(),
          llamadasACrearCamara: creadas,
        );

        expect(find.text('Falta tu autorización'), findsOneWidget);
        expect(find.text('Tomar foto'), findsNothing);
        expect(creadas, isEmpty);
        expect(camara.inicializada, 0);
      });
    }

    testWidgets('con autorizacion vigente abre la camara', (
      WidgetTester tester,
    ) async {
      final _CamaraFalsa camara = _CamaraFalsa();
      await _abrir(
        tester,
        consentimiento: _autorizo(),
        camara: camara,
        recortador: _RecortadorFalso(),
      );

      expect(camara.inicializada, 1);
      expect(find.text('Tomar foto'), findsOneWidget);
    });
  });

  group('tomar la foto', () {
    testWidgets('la foto completa solo llega al recortador', (
      WidgetTester tester,
    ) async {
      final _CamaraFalsa camara = _CamaraFalsa();
      final _RecortadorFalso recortador = _RecortadorFalso(
        resultado: _recorte(),
      );
      await _abrir(
        tester,
        consentimiento: _autorizo(),
        camara: camara,
        recortador: recortador,
      );

      await tester.tap(find.text('Tomar foto'));
      await tester.pumpAndSettle();

      expect(camara.fotos, 1);
      expect(recortador.recibidos, hasLength(1));
      expect(recortador.recibidos.single, _CamaraFalsa.bytesDeLaFoto);
      expect(find.text('Así se verá tu recorte'), findsOneWidget);
    });

    testWidgets('sin rostro pide repetir y no manda nada mas', (
      WidgetTester tester,
    ) async {
      final _CamaraFalsa camara = _CamaraFalsa();
      final _RecortadorFalso recortador = _RecortadorFalso();
      final _Resultado r = await _abrir(
        tester,
        consentimiento: _autorizo(),
        camara: camara,
        recortador: recortador,
      );

      await tester.tap(find.text('Tomar foto'));
      await tester.pumpAndSettle();

      expect(find.text('No vimos tu rostro'), findsOneWidget);
      expect(r.recorte, isNull);

      await tester.tap(find.text('Repetir'));
      await tester.pumpAndSettle();

      expect(find.text('Tomar foto'), findsOneWidget);
      // La camara sigue abierta: repetir no la reabre.
      expect(camara.inicializada, 1);
    });

    testWidgets('un control de calidad fallido sugiere pero no bloquea', (
      WidgetTester tester,
    ) async {
      final _RecortadorFalso recortador = _RecortadorFalso(
        resultado: _recorte(
          fallidos: <ControlCalidad>[ControlCalidad.demasiadosNegros],
        ),
      );
      final _Resultado r = await _abrir(
        tester,
        consentimiento: _autorizo(),
        camara: _CamaraFalsa(),
        recortador: recortador,
      );

      await tester.tap(find.text('Tomar foto'));
      await tester.pumpAndSettle();

      expect(find.text('Podría salir mejor'), findsOneWidget);
      expect(
        find.textContaining(ControlCalidad.demasiadosNegros.recomendacion),
        findsOneWidget,
      );

      // Se puede usar igual.
      await tester.tap(find.text('Usar esta foto'));
      await tester.pumpAndSettle();
      expect(r.recorte, isNotNull);
    });

    testWidgets('avisa cuando salia mas de una persona', (
      WidgetTester tester,
    ) async {
      await _abrir(
        tester,
        consentimiento: _autorizo(),
        camara: _CamaraFalsa(),
        recortador: _RecortadorFalso(resultado: _recorte(variosRostros: true)),
      );

      await tester.tap(find.text('Tomar foto'));
      await tester.pumpAndSettle();

      expect(find.textContaining('más de una persona'), findsOneWidget);
    });

    testWidgets('usar la foto devuelve el recorte y cierra', (
      WidgetTester tester,
    ) async {
      final RecorteFacial recorte = _recorte();
      final _Resultado r = await _abrir(
        tester,
        consentimiento: _autorizo(),
        camara: _CamaraFalsa(),
        recortador: _RecortadorFalso(resultado: recorte),
      );

      await tester.tap(find.text('Tomar foto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Usar esta foto'));
      await tester.pumpAndSettle();

      expect(r.cerro, isTrue);
      expect(r.recorte, same(recorte));
    });

    testWidgets('repetir desde la revision descarta el recorte', (
      WidgetTester tester,
    ) async {
      final _Resultado r = await _abrir(
        tester,
        consentimiento: _autorizo(),
        camara: _CamaraFalsa(),
        recortador: _RecortadorFalso(resultado: _recorte()),
      );

      await tester.tap(find.text('Tomar foto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Repetir'));
      await tester.pumpAndSettle();

      expect(find.text('Tomar foto'), findsOneWidget);
      expect(find.text('Así se verá tu recorte'), findsNothing);
      expect(r.cerro, isFalse);
    });
  });

  group('fallos', () {
    testWidgets('sin camara frontal lo dice y libera la camara', (
      WidgetTester tester,
    ) async {
      final _CamaraFalsa camara = _CamaraFalsa(falla: const SinCamaraFrontal());
      await _abrir(
        tester,
        consentimiento: _autorizo(),
        camara: camara,
        recortador: _RecortadorFalso(),
      );

      expect(find.textContaining('no tiene cámara frontal'), findsOneWidget);
      expect(camara.liberada, 1);
    });

    testWidgets('sin permiso de camara lo dice', (WidgetTester tester) async {
      await _abrir(
        tester,
        consentimiento: _autorizo(),
        camara: _CamaraFalsa(falla: StateError('permiso denegado')),
        recortador: _RecortadorFalso(),
      );

      expect(find.textContaining('permiso'), findsOneWidget);
    });

    testWidgets('sin margenes configurados no pide repetir: es de la build', (
      WidgetTester tester,
    ) async {
      await _abrir(
        tester,
        consentimiento: _autorizo(),
        camara: _CamaraFalsa(),
        recortador: _RecortadorFalso(
          error: const ConfiguracionRecorteInvalida(<String>[
            'falta RECORTE_MARGEN_SUPERIOR',
          ]),
        ),
      );

      await tester.tap(find.text('Tomar foto'));
      await tester.pumpAndSettle();

      expect(find.textContaining('no tiene configurado'), findsOneWidget);
      expect(find.text('Repetir'), findsNothing);
    });

    testWidgets('un perfil de color ilegible no manda la foto de reserva', (
      WidgetTester tester,
    ) async {
      final _RecortadorFalso recortador = _RecortadorFalso(
        error: const PerfilIccNoSoportado('perfil raro'),
      );
      final _Resultado r = await _abrir(
        tester,
        consentimiento: _autorizo(),
        camara: _CamaraFalsa(),
        recortador: recortador,
      );

      await tester.tap(find.text('Tomar foto'));
      await tester.pumpAndSettle();

      expect(find.textContaining('leer el color'), findsOneWidget);
      // Un solo intento, un solo destino, ningun resultado: no hay plan B que
      // envie la foto completa (ADR 0016).
      expect(recortador.recibidos, hasLength(1));
      expect(r.recorte, isNull);
    });
  });

  testWidgets('salir de la pantalla libera la camara', (
    WidgetTester tester,
  ) async {
    final _CamaraFalsa camara = _CamaraFalsa();
    await _abrir(
      tester,
      consentimiento: _autorizo(),
      camara: camara,
      recortador: _RecortadorFalso(),
    );
    expect(camara.liberada, 0);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    expect(camara.liberada, 1);
  });

  group('desde la pantalla de colorimetria', () {
    Future<void> montar(
      WidgetTester tester, {
      required bool conCamara,
      required _CamaraFalsa camara,
    }) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: PantallaColorimetria(
            repositorio: RepositorioFalso(
              latencia: Duration.zero,
              consentimiento: _autorizo(),
            ),
            capturaDisponible: true,
            crearCamara: conCamara ? () => camara : null,
            recortador: conCamara ? _RecortadorFalso() : null,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('con camara, el boton abre la foto', (
      WidgetTester tester,
    ) async {
      final _CamaraFalsa camara = _CamaraFalsa();
      await montar(tester, conCamara: true, camara: camara);

      await tester.tap(find.text('Tomar la foto'));
      await tester.pumpAndSettle();

      expect(find.text('Foto de tu rostro'), findsOneWidget);
      expect(camara.inicializada, 1);
    });

    testWidgets('sin camara conectada, el boton sigue apagado', (
      WidgetTester tester,
    ) async {
      await montar(tester, conCamara: false, camara: _CamaraFalsa());

      final Finder boton = find.widgetWithText(
        FilledButton,
        'Tomar la foto (próximamente)',
      );
      expect(boton, findsOneWidget);
      expect(tester.widget<FilledButton>(boton).onPressed, isNull);
    });
  });
}
