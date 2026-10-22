/// Las tres pantallas del modo de captura, con camara falsa y almacen real.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wearhack/core/color/perfil_icc.dart';
import 'package:wearhack/core/recorte/configuracion_recorte.dart';
import 'package:wearhack/core/recorte/recortador_facial.dart';
import 'package:wearhack/features/captura_pruebas/lote.dart';
import 'package:wearhack/features/captura_pruebas/metadatos.dart';
import 'package:wearhack/features/captura_pruebas/modelos.dart';
import 'package:wearhack/features/captura_pruebas/ui/camara.dart';
import 'package:wearhack/features/captura_pruebas/ui/guia_de_distancia.dart';
import 'package:wearhack/features/captura_pruebas/ui/pantalla_captura.dart';
import 'package:wearhack/features/captura_pruebas/ui/sesion.dart';

import 'helpers/captura_helpers.dart';
import 'helpers/captura_ui_helpers.dart';
import 'helpers/icc_sintetico.dart';

Future<List<String>> _archivos(WidgetTester tester, Montaje m) async =>
    (await tester.runAsync(() => archivosBajo(m.almacen.dirTomas)))!;

void main() {
  group('pantalla de inicio', () {
    testWidgets(
      'Continuar esta deshabilitado hasta tener persona, celular y autorizacion',
      (tester) async {
        final Montaje m = await montar(tester);
        await abrirInicio(tester, m);
        bool habilitado() =>
            tester
                .widget<FilledButton>(find.byKey(const Key('boton_continuar')))
                .onPressed !=
            null;

        expect(habilitado(), isFalse, reason: 'sin nada');

        await elegir(tester, const Key('campo_seudonimo'), 'P3');
        expect(habilitado(), isFalse, reason: 'solo persona');

        await elegir(
          tester,
          const Key('campo_celular'),
          'D2 - Android gama baja',
        );
        expect(
          habilitado(),
          isFalse,
          reason: 'persona y celular, sin autorizacion',
        );

        await tester.tap(find.byKey(const Key('casilla_autorizacion')));
        await tester.pumpAndSettle();
        expect(habilitado(), isTrue);
      },
    );

    testWidgets('quitar la autorizacion vuelve a deshabilitar el boton', (
      tester,
    ) async {
      final Montaje m = await montar(tester);
      await abrirInicio(tester, m);
      await elegir(tester, const Key('campo_seudonimo'), 'P1');
      await elegir(tester, const Key('campo_celular'), 'D1 - iPhone');
      await tester.tap(find.byKey(const Key('casilla_autorizacion')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('casilla_autorizacion')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('boton_continuar')))
            .onPressed,
        isNull,
      );
    });

    testWidgets(
      'Continuar solo se habilita con LAS TRES condiciones: las 8 combinaciones',
      (tester) async {
        // Probar solo una secuencia no basta: hay que ver que si falta
        // exactamente una de las tres, el boton sigue apagado.
        for (final bool persona in <bool>[false, true]) {
          for (final bool celular in <bool>[false, true]) {
            for (final bool autorizacion in <bool>[false, true]) {
              final Montaje m = await montar(tester);
              await tester.pumpWidget(const SizedBox()); // estado nuevo
              await abrirInicio(tester, m);
              if (persona) {
                await elegir(tester, const Key('campo_seudonimo'), 'P2');
              }
              if (celular) {
                await elegir(tester, const Key('campo_celular'), 'D1 - iPhone');
              }
              if (autorizacion) {
                await tester.tap(find.byKey(const Key('casilla_autorizacion')));
                await tester.pumpAndSettle();
              }

              final bool habilitado =
                  tester
                      .widget<FilledButton>(
                        find.byKey(const Key('boton_continuar')),
                      )
                      .onPressed !=
                  null;
              expect(
                habilitado,
                persona && celular && autorizacion,
                reason:
                    'persona=$persona celular=$celular autorizacion=$autorizacion',
              );
            }
          }
        }
      },
    );

    testWidgets('True Tone marcado en el inicio llega al JSON de la toma', (
      tester,
    ) async {
      final Montaje m = await montar(tester);
      await abrirInicio(tester, m);
      await elegir(tester, const Key('campo_seudonimo'), 'P3');
      await elegir(
        tester,
        const Key('campo_celular'),
        'D2 - Android gama baja',
      );
      await tester.tap(find.byKey(const Key('casilla_autorizacion')));
      await tester.tap(find.byKey(const Key('casilla_true_tone')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('boton_continuar')));
      await tester.pump();
      await esperarHasta(
        tester,
        () => find.byKey(const Key('resumen')).evaluate().isNotEmpty,
      );

      await capturarCasilla(tester, 'LEDC', 'R1');

      final Map<String, Object?> json = (await tester.runAsync(
        () => m.almacen.leerMetadatos(idDe()),
      ))!;
      expect(
        (json['pantalla']! as Map<String, Object?>)['true_tone_o_night_shift'],
        isTrue,
      );
    });

    testWidgets('sin marcar True Tone, el JSON dice que no', (tester) async {
      final Montaje m = await montar(tester);
      await llegarALaCuadricula(tester, m);

      await capturarCasilla(tester, 'LEDC', 'R1');

      final Map<String, Object?> json = (await tester.runAsync(
        () => m.almacen.leerMetadatos(idDe()),
      ))!;
      expect(
        (json['pantalla']! as Map<String, Object?>)['true_tone_o_night_shift'],
        isFalse,
      );
    });

    testWidgets('nada viene elegido de antemano', (tester) async {
      final Montaje m = await montar(tester);
      await abrirInicio(tester, m);

      expect(find.text('P3'), findsNothing);
      expect(find.textContaining('D2 -'), findsNothing);
    });

    testWidgets('D3 avisa de que esta reservado', (tester) async {
      final Montaje m = await montar(tester);
      await abrirInicio(tester, m);
      expect(find.byKey(const Key('aviso_d3')), findsNothing);

      await elegir(
        tester,
        const Key('campo_celular'),
        'D3 - Android gama media',
      );

      expect(find.byKey(const Key('aviso_d3')), findsOneWidget);
    });

    testWidgets('muestra el modelo, el sistema y la build, leidos solos', (
      tester,
    ) async {
      final Montaje m = await montar(tester);
      await abrirInicio(tester, m);

      expect(
        find.text('Celular de prueba - Android 14 - app 0.1.0+1'),
        findsOneWidget,
      );
    });

    testWidgets('Continuar lleva a la cuadricula de esa persona y celular', (
      tester,
    ) async {
      final Montaje m = await montar(tester);
      await llegarALaCuadricula(tester, m);

      expect(find.text('P3 - D2'), findsOneWidget);
      expect(find.byKey(const Key('resumen')), findsOneWidget);
    });
  });

  group('cuadricula', () {
    testWidgets('muestra las 15 casillas, todas pendientes', (tester) async {
      final Montaje m = await montar(tester);
      await llegarALaCuadricula(tester, m);

      for (final Luz luz in Luz.values) {
        for (final Repeticion rep in Repeticion.values) {
          expect(
            find.byKey(Key('celda_${luz.codigo}_${rep.codigo}')),
            findsOneWidget,
          );
        }
      }
      expect(find.textContaining('0/15'), findsOneWidget);
      expect(find.text('hecha'), findsNothing);
    });

    testWidgets('solo R1 se anuncia con tarjeta', (tester) async {
      final Montaje m = await montar(tester);
      await llegarALaCuadricula(tester, m);

      expect(find.text('con tarjeta'), findsNWidgets(5));
      expect(find.text('pendiente'), findsNWidgets(10));
    });

    testWidgets('tomar una foto marca la casilla y suma al resumen', (
      tester,
    ) async {
      final Montaje m = await montar(tester);
      await llegarALaCuadricula(tester, m);

      await capturarCasilla(tester, 'LEDC', 'R1');

      expect(find.textContaining('1/15'), findsOneWidget);
      expect(find.text('hecha'), findsOneWidget);
      expect(await _archivos(tester, m), <String>[
        'P3_LEDC_D2_R1_G.json',
        'P3_LEDC_D2_R1_G_foto.jpg',
        'P3_LEDC_D2_R1_G_recorte.png',
      ]);
    });

    testWidgets(
      'las tomas de otra persona no marcan casillas ni entran en este lote',
      (tester) async {
        final Montaje m = await montar(tester);
        final CropperDePrueba cropper = CropperDePrueba();
        final Uint8List foto = fotoDePrueba();
        final RecorteFacial? recorteOpcional = await tester
            .runAsync<RecorteFacial?>(() => cropper.recortar(foto));
        final RecorteFacial recorte = recorteOpcional!;
        await tester.runAsync(
          () => m.almacen.guardarToma(
            id: idDe(seudonimo: 'P5'),
            foto: foto,
            extensionFoto: 'jpg',
            recorte: recorte,
            celular: datosDelCelular(),
            parametrosCamara: const ParametrosDeCamara(),
            momento: DateTime.utc(2026),
          ),
        );

        await llegarALaCuadricula(tester, m);

        expect(find.textContaining('0/15'), findsOneWidget);
        expect(find.textContaining('0 en el lote de P3'), findsOneWidget);
        expect(find.text('hecha'), findsNothing);
      },
    );

    testWidgets(
      'las tomas de la misma persona con OTRO celular no marcan casillas',
      (tester) async {
        final Montaje m = await montar(tester);
        final CropperDePrueba cropper = CropperDePrueba();
        final Uint8List foto = fotoDePrueba();
        final RecorteFacial? recorte = await tester.runAsync<RecorteFacial?>(
          () => cropper.recortar(foto),
        );
        await tester.runAsync(
          () => m.almacen.guardarToma(
            id: idDe(celular: CodigoCelular.d1), // P3 con el iPhone
            foto: foto,
            extensionFoto: 'jpg',
            recorte: recorte!,
            celular: datosDelCelular(codigo: CodigoCelular.d1),
            parametrosCamara: const ParametrosDeCamara(),
            momento: DateTime.utc(2026),
          ),
        );

        // Se abre P3 pero con el celular D2.
        await llegarALaCuadricula(tester, m);

        expect(find.textContaining('0/15'), findsOneWidget);
        expect(find.textContaining('1 en el lote de P3'), findsOneWidget);
        expect(find.text('hecha'), findsNothing);
      },
    );

    testWidgets('tocar una casilla hecha pregunta antes de reemplazar', (
      tester,
    ) async {
      final Montaje m = await montar(tester);
      await llegarALaCuadricula(tester, m);
      await capturarCasilla(tester, 'VEN', 'R2');

      await tester.tap(find.byKey(const Key('celda_VEN_R2')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dialogo_reemplazo')), findsOneWidget);
      expect(find.textContaining('P3_VEN_D2_R2_N'), findsOneWidget);
    });

    testWidgets('cancelar el reemplazo no abre la camara ni toca nada', (
      tester,
    ) async {
      final Montaje m = await montar(tester);
      await llegarALaCuadricula(tester, m);
      await capturarCasilla(tester, 'VEN', 'R2');
      final List<String> antes = await _archivos(tester, m);
      final int fotos = m.camara.fotosTomadas;

      await tester.tap(find.byKey(const Key('celda_VEN_R2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('boton_capturar')), findsNothing);
      expect(m.camara.fotosTomadas, fotos);
      expect(await _archivos(tester, m), antes);
    });

    testWidgets(
      'confirmar el reemplazo deja una sola toma con el contenido nuevo',
      (tester) async {
        final Montaje m = await montar(tester);
        await llegarALaCuadricula(tester, m);
        await capturarCasilla(tester, 'VEN', 'R2');
        final Uint8List primera = (await tester.runAsync(
          () =>
              File('${m.almacen.dirTomas.path}/P3_VEN_D2_R2_N_foto.jpg')
                  .readAsBytes(),
        ))!;

        await tester.tap(find.byKey(const Key('celda_VEN_R2')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirmar_reemplazo')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('boton_capturar')));
        await esperarHasta(
          tester,
          () => find.byKey(const Key('resumen')).evaluate().isNotEmpty,
        );

        final Uint8List segunda = (await tester.runAsync(
          () =>
              File('${m.almacen.dirTomas.path}/P3_VEN_D2_R2_N_foto.jpg')
                  .readAsBytes(),
        ))!;
        expect(segunda, isNot(primera));
        expect(await _archivos(tester, m), hasLength(3));
        expect(find.textContaining('1/15'), findsOneWidget);
      },
    );

    testWidgets('exportar comparte el zip y avisa', (tester) async {
      final Montaje m = await montar(tester);
      await llegarALaCuadricula(tester, m);
      await capturarCasilla(tester, 'LEDC', 'R1');

      await tester.tap(find.byKey(const Key('boton_exportar')));
      await esperarHasta(
        tester,
        () => find.textContaining('Lote exportado').evaluate().isNotEmpty,
      );

      expect(m.compartidos, hasLength(1));
      expect(m.compartidos.single.path, endsWith('.zip'));
      expect(await tester.runAsync(m.compartidos.single.exists), isTrue);
    });

    testWidgets('exportar sin tomas avisa y no comparte nada', (tester) async {
      final Montaje m = await montar(tester);
      await llegarALaCuadricula(tester, m);

      await tester.tap(find.byKey(const Key('boton_exportar')));
      await esperarHasta(
        tester,
        () => find.textContaining('No hay tomas').evaluate().isNotEmpty,
      );

      expect(m.compartidos, isEmpty);
    });

    testWidgets('borrar con un texto equivocado lo dice y no borra nada', (
      tester,
    ) async {
      final Montaje m = await montar(tester);
      await llegarALaCuadricula(tester, m);
      await capturarCasilla(tester, 'LEDC', 'R1');
      final List<String> antes = await _archivos(tester, m);

      await tester.tap(find.byKey(const Key('boton_borrar')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('campo_confirmacion')),
        '00000000',
      );
      await tester.tap(find.byKey(const Key('confirmar_borrado')));
      await esperarHasta(
        tester,
        () => find.byKey(const Key('error_borrado')).evaluate().isNotEmpty,
      );

      expect(find.textContaining('No coincide'), findsOneWidget);
      expect(
        find.byKey(const Key('dialogo_borrado')),
        findsOneWidget,
        reason: 'sigue abierto',
      );
      expect(await _archivos(tester, m), antes);
    });

    testWidgets('borrar con el prefijo correcto vacia el lote', (tester) async {
      final Montaje m = await montar(tester);
      await llegarALaCuadricula(tester, m);
      await capturarCasilla(tester, 'LEDC', 'R1');
      final Manifiesto manifiesto = (await tester.runAsync(
        () => calcularManifiesto(m.almacen),
      ))!;

      await tester.tap(find.byKey(const Key('boton_borrar')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('campo_confirmacion')),
        manifiesto.prefijoDeConfirmacion,
      );
      await tester.tap(find.byKey(const Key('confirmar_borrado')));
      await esperarHasta(
        tester,
        () => find.textContaining('Lote de P3 borrado').evaluate().isNotEmpty,
      );

      await asentar(tester, rondas: 20);
      expect(find.textContaining('0/15'), findsOneWidget);
      expect(await _archivos(tester, m), isEmpty);
      expect(await tester.runAsync(() => archivosBajo(m.raiz)), isEmpty);
    });
  });

  group('pantalla de captura', () {
    SesionCaptura sesion({bool autorizacion = true, bool trueTone = false}) =>
        SesionCaptura(
          seudonimo: Seudonimo('P3'),
          celular: CodigoCelular.d2,
          autorizacionFirmada: autorizacion,
          trueToneONightShift: trueTone,
        );

    Future<void> abrirCaptura(
      WidgetTester tester,
      Montaje m, {
      Repeticion rep = Repeticion.r1,
      SesionCaptura? s,
      bool reemplazar = false,
    }) async {
      pantallaDeTelefono(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: PantallaCaptura(
            dependencias: m.dependencias,
            sesion: s ?? sesion(),
            id: idDe(repeticion: rep),
            reemplazar: reemplazar,
          ),
        ),
      );
      await asentar(tester);
    }

    testWidgets('R1 pide poner la tarjeta gris', (tester) async {
      final Montaje m = await montar(tester);
      await abrirCaptura(tester, m);

      expect(find.text('Pon la tarjeta gris junto al rostro'), findsOneWidget);
      expect(find.byKey(const Key('vista_previa')), findsOneWidget);
    });

    testWidgets('R2 y R3 piden retirarla', (tester) async {
      for (final Repeticion rep in <Repeticion>[Repeticion.r2, Repeticion.r3]) {
        final Montaje m = await montar(tester);
        await abrirCaptura(tester, m, rep: rep);

        expect(
          find.text('Retira la tarjeta gris'),
          findsOneWidget,
          reason: rep.codigo,
        );
      }
    });

    testWidgets('si no hay camara frontal lo dice y no ofrece capturar', (
      tester,
    ) async {
      final Montaje m = await montar(
        tester,
        camara: CamaraFalsa(falloAlAbrir: const SinCamaraFrontal()),
      );
      await abrirCaptura(tester, m);

      expect(find.textContaining('no tiene camara frontal'), findsOneWidget);
      expect(find.byKey(const Key('boton_capturar')), findsNothing);
    });

    testWidgets('si falla el permiso lo cuenta', (tester) async {
      final Montaje m = await montar(
        tester,
        camara: CamaraFalsa(falloAlAbrir: StateError('permiso denegado')),
      );
      await abrirCaptura(tester, m);

      expect(find.textContaining('No se pudo abrir la camara'), findsOneWidget);
      expect(find.byKey(const Key('boton_capturar')), findsNothing);
    });

    testWidgets('guarda la toma con los datos del celular y de la sesion', (
      tester,
    ) async {
      final Montaje m = await montar(tester);
      await abrirCaptura(tester, m, s: sesion(trueTone: true));

      await tester.tap(find.byKey(const Key('boton_capturar')));
      await esperarHasta(tester, () => m.camara.fotosTomadas == 1);
      await asentar(tester, rondas: 20);

      final Map<String, Object?> json = (await tester.runAsync(
        () => m.almacen.leerMetadatos(idDe()),
      ))!;
      expect(
        (json['celular']! as Map<String, Object?>)['modelo'],
        'Celular de prueba',
      );
      expect((json['celular']! as Map<String, Object?>)['codigo'], 'D2');
      expect(
        (json['pantalla']! as Map<String, Object?>)['true_tone_o_night_shift'],
        isTrue,
      );
      expect(json['tarjeta_gris'], isTrue);
      expect(json['fecha_hora'], contains('2026-10-15'));
    });

    testWidgets('sin rostro no guarda nada y deja repetir', (tester) async {
      final Montaje m = await montar(
        tester,
        cropper: CropperDePrueba(cajas: <CajaRostro>[]),
      );
      await abrirCaptura(tester, m);

      await tester.tap(find.byKey(const Key('boton_capturar')));
      await esperarHasta(
        tester,
        () => find.byKey(const Key('mensaje')).evaluate().isNotEmpty,
      );

      expect(find.textContaining('No se vio un rostro'), findsOneWidget);
      expect(await _archivos(tester, m), isEmpty);
      expect(
        tester
            .widget<FloatingActionButton>(
              find.byKey(const Key('boton_capturar')),
            )
            .onPressed,
        isNotNull,
        reason: 'el boton vuelve a estar disponible',
      );
    });

    testWidgets(
      'si faltan los margenes del recorte lo dice con el nombre del parametro',
      (tester) async {
        final Montaje m = await montar(
          tester,
          cropper: CropperQueFalla(
            const ConfiguracionRecorteInvalida(<String>[
              'falta RECORTE_MARGEN_SUPERIOR',
            ]),
          ),
        );
        await abrirCaptura(tester, m);

        await tester.tap(find.byKey(const Key('boton_capturar')));
        await esperarHasta(
          tester,
          () => find.byKey(const Key('mensaje')).evaluate().isNotEmpty,
        );

        expect(find.textContaining('RECORTE_MARGEN_SUPERIOR'), findsOneWidget);
        expect(await _archivos(tester, m), isEmpty);
      },
    );

    testWidgets('un perfil de color ilegible se cuenta y no guarda nada', (
      tester,
    ) async {
      final Montaje m = await montar(
        tester,
        cropper: CropperQueFalla(
          const PerfilIccNoSoportado('es un perfil de LUT'),
        ),
      );
      await abrirCaptura(tester, m);

      await tester.tap(find.byKey(const Key('boton_capturar')));
      await esperarHasta(
        tester,
        () => find.byKey(const Key('mensaje')).evaluate().isNotEmpty,
      );

      expect(find.textContaining('es un perfil de LUT'), findsOneWidget);
      expect(await _archivos(tester, m), isEmpty);
    });

    testWidgets(
      'sin la autorizacion firmada el servicio se niega aunque se pulse el boton',
      (tester) async {
        final Montaje m = await montar(tester);
        await abrirCaptura(tester, m, s: sesion(autorizacion: false));

        await tester.tap(find.byKey(const Key('boton_capturar')));
        await esperarHasta(
          tester,
          () => find.byKey(const Key('mensaje')).evaluate().isNotEmpty,
        );

        expect(find.textContaining('autorizacion'), findsOneWidget);
        expect(await _archivos(tester, m), isEmpty);
      },
    );

    testWidgets('un segundo toque mientras se guarda no toma otra foto', (
      tester,
    ) async {
      final Completer<void> espera = Completer<void>();
      final Montaje m = await montar(
        tester,
        camara: CamaraFalsa(retener: espera),
      );
      await abrirCaptura(tester, m);

      await tester.tap(find.byKey(const Key('boton_capturar')));
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('boton_capturar')),
        warnIfMissed: false,
      );
      await tester.pump();

      expect(m.camara.fotosTomadas, 1);
      expect(
        tester
            .widget<FloatingActionButton>(
              find.byKey(const Key('boton_capturar')),
            )
            .onPressed,
        isNull,
      );
      espera.complete();
      await asentar(tester, rondas: 20);
    });

    testWidgets('al salir de la pantalla se libera la camara', (tester) async {
      final Montaje m = await montar(tester);
      await abrirCaptura(tester, m);
      expect(m.camara.liberada, isFalse);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();

      expect(m.camara.liberada, isTrue);
    });

    group('calidad', () {
      Future<Montaje> conUmbral(
        WidgetTester tester, {
        CamaraFalsa? camara,
      }) async {
        final RecortadorFacial real = RecortadorFacial(
          detector: DetectorFalso(<CajaRostro>[cajaDePrueba]),
          configuracion: const ConfiguracionRecorte(
            margenSuperior: 0.5,
            margenInferior: 0.25,
            margenLateral: 0.5,
            maxQuemadosPct: 5,
          ),
        );
        return montar(
          tester,
          camara: camara,
          cropper: CropperConConfiguracion(real.recortar),
        );
      }

      Uint8List blanca() =>
          jpegSintetico(400, 400, color: (int x, int y) => (255, 255, 255));

      testWidgets(
        'un control fallido guarda la toma y sugiere repetir con la razon concreta',
        (tester) async {
          final Montaje m = await conUmbral(
            tester,
            camara: CamaraFalsa(fotos: <Uint8List>[blanca()]),
          );
          await abrirCaptura(tester, m);

          await tester.tap(find.byKey(const Key('boton_capturar')));
          await esperarHasta(
            tester,
            () =>
                find.byKey(const Key('dialogo_calidad')).evaluate().isNotEmpty,
          );

          expect(find.textContaining('demasiada luz'), findsOneWidget);
          expect(
            await _archivos(tester, m),
            hasLength(3),
            reason: 'ya se guardo',
          );
        },
      );

      testWidgets('Conservar cierra la pantalla con la toma guardada', (
        tester,
      ) async {
        final Montaje m = await conUmbral(
          tester,
          camara: CamaraFalsa(fotos: <Uint8List>[blanca()]),
        );
        await llegarALaCuadricula(tester, m);
        await tester.tap(find.byKey(const Key('celda_LEDC_R1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('boton_capturar')));
        await esperarHasta(
          tester,
          () => find.byKey(const Key('dialogo_calidad')).evaluate().isNotEmpty,
        );

        await tester.tap(find.byKey(const Key('conservar_toma')));
        await esperarHasta(
          tester,
          () => find.byKey(const Key('resumen')).evaluate().isNotEmpty,
        );
        await asentar(tester, rondas: 20);

        expect(find.textContaining('1/15'), findsOneWidget);
      });

      testWidgets(
        'Repetir se queda en la camara y la siguiente toma reemplaza a la anterior',
        (tester) async {
          final Uint8List buena = fotoDePrueba(semilla: 3);
          final Montaje m = await conUmbral(
            tester,
            camara: CamaraFalsa(fotos: <Uint8List>[blanca(), buena]),
          );
          await abrirCaptura(tester, m);

          await tester.tap(find.byKey(const Key('boton_capturar')));
          await esperarHasta(
            tester,
            () =>
                find.byKey(const Key('dialogo_calidad')).evaluate().isNotEmpty,
          );
          await tester.tap(find.byKey(const Key('repetir_toma')));
          await tester.pumpAndSettle();

          expect(
            find.byKey(const Key('boton_capturar')),
            findsOneWidget,
            reason: 'sigue en la camara',
          );
          await tester.tap(find.byKey(const Key('boton_capturar')));
          await esperarHasta(tester, () => m.camara.fotosTomadas == 2);
          await asentar(tester, rondas: 20);

          expect(m.camara.fotosTomadas, 2);
          expect(
            await _archivos(tester, m),
            hasLength(3),
            reason: 'reemplazo, no una toma mas',
          );
          expect(
            find.byKey(const Key('dialogo_calidad')),
            findsNothing,
            reason: 'la buena pasa',
          );
          // Lo decisivo: lo guardado es la foto BUENA, y no hubo ningun error.
          // Sin marcar el reemplazo, la segunda toma choca con TomaYaExiste, no
          // se guarda, y el disco se queda con la foto quemada.
          expect(
            find.byKey(const Key('mensaje')),
            findsNothing,
            reason: 'no debe haber un error como "esa toma ya existe"',
          );
          final Uint8List guardada = (await tester.runAsync(
            () =>
                File('${m.almacen.dirTomas.path}/P3_LEDC_D2_R1_G_foto.jpg')
                    .readAsBytes(),
          ))!;
          expect(guardada, buena, reason: 'la foto quemada fue reemplazada');
        },
      );
    });

    group('guia de distancia', () {
      testWidgets('apagada, lo dice y no pretende medir', (tester) async {
        final Montaje m = await montar(tester);
        await abrirCaptura(tester, m);

        expect(
          find.textContaining('Guia de distancia apagada'),
          findsOneWidget,
        );
      });

      testWidgets(
        'encendida y sin calibrar, muestra el ancho que mide para poder calibrar',
        (tester) async {
          final CamaraFalsa camara = CamaraFalsa(guiaActiva: true);
          final Montaje m = await montar(tester, camara: camara);
          await abrirCaptura(tester, m);

          camara.anchos.add(433);
          await asentar(tester, rondas: 3);

          expect(find.textContaining('sin calibrar'), findsOneWidget);
          expect(find.textContaining('433 px'), findsOneWidget);
        },
      );

      testWidgets('calibrada, dice si esta lejos, bien o cerca', (
        tester,
      ) async {
        final CamaraFalsa camara = CamaraFalsa(guiaActiva: true);
        final Montaje m = await montar(
          tester,
          camara: camara,
          rango: (CodigoCelular c) =>
              const RangoDeAncho(minimo: 380, maximo: 520),
        );
        await abrirCaptura(tester, m);

        camara.anchos.add(300);
        await asentar(tester, rondas: 3);
        expect(find.textContaining('Acercate'), findsOneWidget);

        camara.anchos.add(450);
        await asentar(tester, rondas: 3);
        expect(find.text('Distancia correcta'), findsOneWidget);

        camara.anchos.add(600);
        await asentar(tester, rondas: 3);
        expect(find.textContaining('Alejate'), findsOneWidget);

        camara.anchos.add(null);
        await asentar(tester, rondas: 3);
        expect(find.text('No se ve un rostro'), findsOneWidget);
      });
    });
  });

  group('espejo de la camara en la pantalla de captura', () {
    for (final bool? valor in <bool?>[true, false, null]) {
      testWidgets('lo que la camara dice ($valor) queda en el JSON', (
        tester,
      ) async {
        final Montaje m = await montar(
          tester,
          camara: CamaraFalsa(espejo: valor),
        );
        await llegarALaCuadricula(tester, m);
        await capturarCasilla(tester, 'LEDC', 'R1');

        final Map<String, Object?> json = (await tester.runAsync(
          () => m.almacen.leerMetadatos(idDe()),
        ))!;
        final Map<String, Object?> camara =
            json['camara']! as Map<String, Object?>;
        expect(camara['espejo'], valor);
      });
    }
  });

  group('un lote por persona', () {
    testWidgets('los botones dicen de quien es el lote', (tester) async {
      final Montaje m = await montar(tester);
      await llegarALaCuadricula(tester, m, persona: 'P5');

      expect(find.text('Exportar lote P5'), findsOneWidget);
      expect(find.text('Borrar lote P5'), findsOneWidget);
    });

    testWidgets('exportar comparte solo el zip de esa persona', (tester) async {
      final Montaje m = await montar(tester);
      await tester.runAsync(() => agregarTomas(m.almacen, 2, seudonimo: 'P4'));
      await llegarALaCuadricula(tester, m);
      await capturarCasilla(tester, 'LEDC', 'R1');

      await tester.tap(find.byKey(const Key('boton_exportar')));
      await esperarHasta(
        tester,
        () => find.textContaining('Lote exportado').evaluate().isNotEmpty,
      );

      final File zip = m.compartidos.single;
      expect(zip.uri.pathSegments.last, startsWith('lote_P3_'));
      final Archive contenido = (await tester.runAsync(
        () async => ZipDecoder().decodeBytes(await zip.readAsBytes()),
      ))!;
      final List<String> nombres = <String>[
        for (final ArchiveFile f in contenido.files)
          if (f.name != nombreManifiesto) f.name,
      ];
      expect(nombres, hasLength(3));
      expect(nombres, everyElement(startsWith('P3_')));
    });

    testWidgets('el resumen cuenta solo el lote de esa persona', (
      tester,
    ) async {
      final Montaje m = await montar(tester);
      await tester.runAsync(() => agregarTomas(m.almacen, 4, seudonimo: 'P4'));
      await llegarALaCuadricula(tester, m);
      await capturarCasilla(tester, 'LEDC', 'R1');

      expect(find.textContaining('1/15'), findsOneWidget);
      expect(find.textContaining('1 en el lote de P3'), findsOneWidget);
    });

    testWidgets('despues de borrar limpia la copia temporal del zip', (
      tester,
    ) async {
      int limpiezas = 0;
      final Montaje m = await montar(
        tester,
        limpiarTemporales: () async => limpiezas++,
      );
      await llegarALaCuadricula(tester, m);
      await capturarCasilla(tester, 'LEDC', 'R1');
      final Manifiesto manifiesto = (await tester.runAsync(
        () => calcularManifiesto(m.almacen, persona: Seudonimo('P3')),
      ))!;
      expect(limpiezas, 0, reason: 'no se limpia antes de borrar');

      await tester.tap(find.byKey(const Key('boton_borrar')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('campo_confirmacion')),
        manifiesto.prefijoDeConfirmacion,
      );
      await tester.tap(find.byKey(const Key('confirmar_borrado')));
      await esperarHasta(
        tester,
        () => find.textContaining('Lote de P3 borrado').evaluate().isNotEmpty,
      );

      expect(limpiezas, 1);
    });

    testWidgets('con un texto equivocado no limpia nada', (tester) async {
      int limpiezas = 0;
      final Montaje m = await montar(
        tester,
        limpiarTemporales: () async => limpiezas++,
      );
      await llegarALaCuadricula(tester, m);
      await capturarCasilla(tester, 'LEDC', 'R1');

      await tester.tap(find.byKey(const Key('boton_borrar')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('campo_confirmacion')),
        '00000000',
      );
      await tester.tap(find.byKey(const Key('confirmar_borrado')));
      await esperarHasta(
        tester,
        () => find.byKey(const Key('error_borrado')).evaluate().isNotEmpty,
      );

      expect(limpiezas, 0);
    });

    testWidgets('si la limpieza falla, el lote ya esta borrado y se avisa', (
      tester,
    ) async {
      final Montaje m = await montar(
        tester,
        limpiarTemporales: () async => throw const FileSystemException('x'),
      );
      await llegarALaCuadricula(tester, m);
      await capturarCasilla(tester, 'LEDC', 'R1');
      final Manifiesto manifiesto = (await tester.runAsync(
        () => calcularManifiesto(m.almacen, persona: Seudonimo('P3')),
      ))!;

      await tester.tap(find.byKey(const Key('boton_borrar')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('campo_confirmacion')),
        manifiesto.prefijoDeConfirmacion,
      );
      await tester.tap(find.byKey(const Key('confirmar_borrado')));
      await esperarHasta(
        tester,
        () => find.textContaining('copia temporal').evaluate().isNotEmpty,
      );

      expect(await _archivos(tester, m), isEmpty);
    });

    testWidgets('borrar deja intactas las tomas de las demas personas', (
      tester,
    ) async {
      final Montaje m = await montar(tester);
      await tester.runAsync(() => agregarTomas(m.almacen, 2, seudonimo: 'P4'));
      final List<String> deP4 = (await _archivos(
        tester,
        m,
      )).where((String r) => r.startsWith('P4_')).toList();
      await llegarALaCuadricula(tester, m);
      await capturarCasilla(tester, 'LEDC', 'R1');
      final Manifiesto manifiesto = (await tester.runAsync(
        () => calcularManifiesto(m.almacen, persona: Seudonimo('P3')),
      ))!;

      await tester.tap(find.byKey(const Key('boton_borrar')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Borrar el lote de P3'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('campo_confirmacion')),
        manifiesto.prefijoDeConfirmacion,
      );
      await tester.tap(find.byKey(const Key('confirmar_borrado')));
      await esperarHasta(
        tester,
        () => find.textContaining('Lote de P3 borrado').evaluate().isNotEmpty,
      );

      expect(await _archivos(tester, m), deP4);
    });
  });

  group('tomas incompletas al abrir el modo', () {
    Future<void> dejarHuerfanos(WidgetTester tester, Montaje m) async {
      await tester.runAsync(() async {
        m.almacen.dirTomas.createSync(recursive: true);
        File('${m.almacen.dirTomas.path}/P3_VEN_D2_R1_G_foto.jpg')
            .writeAsBytesSync(<int>[1, 2, 3]);
        File('${m.almacen.dirTomas.path}/P3_VEN_D2_R1_G_recorte.png.tmp')
            .writeAsBytesSync(<int>[4]);
      });
    }

    testWidgets('sin tomas incompletas no pregunta nada', (tester) async {
      final Montaje m = await montar(tester);
      await abrirInicio(tester, m);
      await asentar(tester, rondas: 10);

      expect(find.byKey(const Key('dialogo_incompletas')), findsNothing);
    });

    testWidgets('con tomas incompletas las nombra y pide confirmacion', (
      tester,
    ) async {
      final Montaje m = await montar(tester);
      await dejarHuerfanos(tester, m);

      await abrirInicio(tester, m);
      await esperarHasta(
        tester,
        () =>
            find.byKey(const Key('dialogo_incompletas')).evaluate().isNotEmpty,
      );

      expect(find.textContaining('2 archivos'), findsOneWidget);
      expect(find.textContaining('P3_VEN_D2_R1_G_foto.jpg'), findsOneWidget);
      expect(
        await _archivos(tester, m),
        hasLength(2),
        reason: 'no borra nada sin confirmar',
      );
    });

    testWidgets('Conservar no borra nada', (tester) async {
      final Montaje m = await montar(tester);
      await dejarHuerfanos(tester, m);
      await abrirInicio(tester, m);
      await esperarHasta(
        tester,
        () =>
            find.byKey(const Key('dialogo_incompletas')).evaluate().isNotEmpty,
      );

      await tester.tap(find.byKey(const Key('conservar_incompletas')));
      await asentar(tester, rondas: 10);

      expect(find.byKey(const Key('dialogo_incompletas')), findsNothing);
      expect(await _archivos(tester, m), hasLength(2));
    });

    testWidgets('Borrar quita los sueltos y respeta las tomas completas', (
      tester,
    ) async {
      final Montaje m = await montar(tester);
      await tester.runAsync(() => agregarTomas(m.almacen, 2, seudonimo: 'P4'));
      final List<String> completas = await _archivos(tester, m);
      await dejarHuerfanos(tester, m);
      await abrirInicio(tester, m);
      await esperarHasta(
        tester,
        () =>
            find.byKey(const Key('dialogo_incompletas')).evaluate().isNotEmpty,
      );

      await tester.tap(find.byKey(const Key('confirmar_borrar_incompletas')));
      await esperarHasta(
        tester,
        () => find.textContaining('Borrados 2 archivos').evaluate().isNotEmpty,
      );

      expect(await _archivos(tester, m), completas);
    });
  });
}
