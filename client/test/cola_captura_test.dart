/// La cola de captura y de subida (issue #11).
///
/// Se prueba sin disco, sin modelos y sin red: un almacen en memoria, un
/// procesador y un subidor falsos, y un reloj que solo avanza cuando se le dice.
/// Las metas de tiempo (siguiente foto p95 <= 1 s, <= 2 s por prenda) y la
/// pausa por calor real solo se miden en el telefono de referencia.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wearhack/core/vocabulario.dart';
import 'package:wearhack/features/closet/captura/cola_captura.dart';
import 'package:wearhack/features/closet/captura/item_cola.dart';
import 'package:wearhack/platform/captura/contratos.dart';

import 'helpers/cola_helpers.dart';

/// Todo lo que una prueba necesita, junto, y una forma de reabrir la cola sobre
/// el mismo almacen para simular que la app se cerro.
class _Entorno {
  final AlmacenEnMemoria almacen = AlmacenEnMemoria();
  final ProcesadorFalso procesador = ProcesadorFalso();
  final SubidorFalso subidor = SubidorFalso();
  final TermicoFalso termico = TermicoFalso();
  final RelojFalso reloj = RelojFalso();
  final List<Duration> esperas = <Duration>[];
  int _n = 0;

  Future<ColaCaptura> abrir({
    ConfiguracionCola configuracion = const ConfiguracionCola(),
    bool automatica = false,
    Future<void> Function(Duration)? esperar,
  }) => ColaCaptura.abrir(
    almacen: almacen,
    procesador: procesador,
    subidor: subidor,
    termico: termico,
    configuracion: configuracion,
    ahora: reloj.call,
    // Esperar adelanta el reloj: asi la cola no gira en vacio mirando un reloj
    // que no avanza.
    esperar:
        esperar ??
        (Duration d) async {
          esperas.add(d);
          reloj.avanzar(d);
        },
    generarId: () => 'f${++_n}',
    automatica: automatica,
  );
}

/// Un fallo de red que deja la subida en espera.
Object get _sinRed => const SinConexion('sin red');

ItemCola _item(ColaCaptura cola, String id) =>
    cola.items.firstWhere((ItemCola i) => i.id == id);

void main() {
  group('encolar', () {
    test('guarda la foto antes que el indice y no procesa nada', () async {
      final _Entorno e = _Entorno();
      final ColaCaptura cola = await e.abrir();

      final String id = await cola.encolar(foto(1));

      expect(id, 'f1');
      expect(e.almacen.bitacora, <String>['original:f1', 'indice']);
      expect(cola.items.single.estado, EstadoItem.porProcesar);
      expect(e.procesador.lotes, isEmpty);
    });

    test('con el tope lleno falla y no escribe nada', () async {
      final _Entorno e = _Entorno();
      final ColaCaptura cola = await e.abrir(
        configuracion: const ConfiguracionCola(maxPendientes: 2),
      );
      await cola.encolar(foto(1));
      await cola.encolar(foto(2));

      await expectLater(cola.encolar(foto(3)), throwsA(isA<ColaLlena>()));

      expect(e.almacen.originales.keys, <String>['f1', 'f2']);
      expect(cola.items, hasLength(2));
    });

    test('las fallidas no cuentan para el tope', () async {
      final _Entorno e = _Entorno();
      e.procesador.fallaTodo = true;
      final ColaCaptura cola = await e.abrir(
        configuracion: const ConfiguracionCola(
          maxPendientes: 1,
          maxIntentos: 1,
        ),
      );
      await cola.encolar(foto(1));
      await cola.ronda();
      expect(_item(cola, 'f1').estado, EstadoItem.fallida);

      await cola.encolar(foto(2));

      expect(cola.pendientes, 1);
    });
  });

  group('procesar', () {
    test('toma lotes de hasta cinco', () async {
      final _Entorno e = _Entorno();
      final ColaCaptura cola = await e.abrir();
      for (int i = 1; i <= 7; i++) {
        await cola.encolar(foto(i));
      }
      // Sin red, para que la subida no vacie la cola entre rondas.
      e.subidor.guion.add(_sinRed);

      expect(await cola.ronda(), Duration.zero);
      expect(e.procesador.lotes, <int>[5]);

      await cola.ronda();
      expect(e.procesador.lotes, <int>[5, 2]);
    });

    test('cada foto procesada guarda su PNG y pasa a por subir', () async {
      final _Entorno e = _Entorno();
      final ColaCaptura cola = await e.abrir();
      await cola.encolar(foto(1));
      e.subidor.guion.add(_sinRed);

      await cola.ronda();

      final ItemCola item = _item(cola, 'f1');
      expect(item.estado, EstadoItem.porSubir);
      expect(item.datos!.tipo, TipoPrenda.camiseta);
      expect(e.almacen.procesadas, contains('f1'));
      // La original sigue: todavia no se subio.
      expect(e.almacen.originales, contains('f1'));
    });

    test('el fallo de una foto no tumba al resto del lote', () async {
      final _Entorno e = _Entorno();
      e.procesador.fallanLasQueEmpiezanPor.add(2);
      final ColaCaptura cola = await e.abrir();
      for (int i = 1; i <= 3; i++) {
        await cola.encolar(foto(i));
      }
      e.subidor.guion.add(_sinRed);

      await cola.ronda();

      expect(_item(cola, 'f1').estado, EstadoItem.porSubir);
      expect(_item(cola, 'f3').estado, EstadoItem.porSubir);
      final ItemCola fallo = _item(cola, 'f2');
      expect(fallo.estado, EstadoItem.porProcesar);
      expect(fallo.intentos, 1);
      expect(fallo.ultimoError, contains('no se pudo con la foto 2'));
    });

    test('si todo el lote falla, cada foto cuenta su intento', () async {
      final _Entorno e = _Entorno();
      e.procesador.fallaTodo = true;
      final ColaCaptura cola = await e.abrir();
      await cola.encolar(foto(1));
      await cola.encolar(foto(2));

      await cola.ronda();

      expect(cola.items.map((ItemCola i) => i.intentos), <int>[1, 1]);
      expect(cola.items.every((ItemCola i) => i.pendiente), isTrue);
    });

    test(
      'tras agotar los intentos queda fallida y conserva la original',
      () async {
        final _Entorno e = _Entorno();
        e.procesador.fallaTodo = true;
        final ColaCaptura cola = await e.abrir(
          configuracion: const ConfiguracionCola(
            maxIntentos: 3,
            esperaBase: Duration(seconds: 1),
          ),
        );
        await cola.encolar(foto(1));

        // Cada fallo espera el doble que el anterior.
        expect(await cola.ronda(), const Duration(seconds: 1));
        e.reloj.avanzar(const Duration(seconds: 1));
        expect(await cola.ronda(), const Duration(seconds: 2));
        e.reloj.avanzar(const Duration(seconds: 2));
        expect(await cola.ronda(), isNull);

        expect(_item(cola, 'f1').estado, EstadoItem.fallida);
        expect(e.almacen.originales, contains('f1'));
      },
    );

    test(
      'una foto en espera de reintento no se procesa antes de tiempo',
      () async {
        final _Entorno e = _Entorno();
        e.procesador.fallaTodo = true;
        final ColaCaptura cola = await e.abrir();
        await cola.encolar(foto(1));
        await cola.ronda();
        expect(e.procesador.lotes, hasLength(1));

        e.reloj.avanzar(const Duration(seconds: 1)); // el retroceso es de 2 s
        await cola.ronda();

        expect(e.procesador.lotes, hasLength(1));
      },
    );

    test(
      'reintentar las fallidas las devuelve al paso que les faltaba',
      () async {
        final _Entorno e = _Entorno();
        e.procesador.fallaTodo = true;
        final ColaCaptura cola = await e.abrir(
          configuracion: const ConfiguracionCola(maxIntentos: 1),
        );
        await cola.encolar(foto(1));
        await cola.ronda();
        expect(_item(cola, 'f1').estado, EstadoItem.fallida);

        e.procesador.fallaTodo = false;
        await cola.reintentarFallidas();
        expect(_item(cola, 'f1').estado, EstadoItem.porProcesar);
        expect(_item(cola, 'f1').intentos, 0);

        expect(await cola.ronda(), isNull);
        expect(e.subidor.subidos, <String>['f1']);
      },
    );

    test(
      'una original que falta se marca fallida sin tumbar el lote',
      () async {
        final _Entorno e = _Entorno();
        final ColaCaptura cola = await e.abrir();
        await cola.encolar(foto(1));
        await cola.encolar(foto(2));
        e.almacen.originales.remove('f1');

        await cola.ronda();

        expect(_item(cola, 'f1').estado, EstadoItem.fallida);
        expect(_item(cola, 'f1').ultimoError, contains('No se pudo leer'));
        expect(e.subidor.subidos, <String>['f2']);
      },
    );

    test('descartar borra la foto y sus archivos', () async {
      final _Entorno e = _Entorno();
      e.procesador.fallaTodo = true;
      final ColaCaptura cola = await e.abrir(
        configuracion: const ConfiguracionCola(maxIntentos: 1),
      );
      await cola.encolar(foto(1));
      await cola.ronda();

      await cola.descartar('f1');

      expect(cola.items, isEmpty);
      expect(e.almacen.originales, isEmpty);
      expect(e.almacen.indice, isEmpty);
    });
  });

  group('subir', () {
    test('sube y solo entonces borra la original y la procesada', () async {
      final _Entorno e = _Entorno();
      final ColaCaptura cola = await e.abrir();
      await cola.encolar(foto(1));

      expect(await cola.ronda(), isNull);

      expect(e.subidor.subidos, <String>['f1']);
      expect(e.almacen.originales, isEmpty);
      expect(e.almacen.procesadas, isEmpty);
      expect(cola.items, isEmpty);
      // Primero sale del indice, despues se borran los archivos: ver
      // `almacen_cola.dart`.
      final List<String> b = e.almacen.bitacora;
      expect(b.last, 'borrar:f1');
      expect(b[b.length - 2], 'indice');
      expect(e.almacen.indice, isEmpty);
    });

    test('si la subida falla, no se borra nada', () async {
      final _Entorno e = _Entorno();
      e.subidor.guion.add(StateError('el servidor dijo que no'));
      final ColaCaptura cola = await e.abrir();
      await cola.encolar(foto(1));

      await cola.ronda();

      expect(e.almacen.originales, contains('f1'));
      expect(e.almacen.procesadas, contains('f1'));
      final ItemCola item = _item(cola, 'f1');
      expect(item.estado, EstadoItem.porSubir);
      expect(item.intentos, 1);
      expect(item.ultimoError, contains('el servidor dijo que no'));
    });

    test('subir con error mas de maxIntentos veces la deja fallida', () async {
      final _Entorno e = _Entorno();
      e.subidor.guion.addAll(<Object?>[
        StateError('1'),
        StateError('2'),
        StateError('3'),
      ]);
      final ColaCaptura cola = await e.abrir(
        configuracion: const ConfiguracionCola(maxIntentos: 3),
      );
      await cola.encolar(foto(1));

      await cola.ronda();
      e.reloj.avanzar(const Duration(seconds: 2));
      await cola.ronda();
      e.reloj.avanzar(const Duration(seconds: 4));
      await cola.ronda();

      expect(_item(cola, 'f1').estado, EstadoItem.fallida);
      // La imagen procesada y la original siguen para poder reintentar.
      expect(e.almacen.procesadas, contains('f1'));
      expect(e.almacen.originales, contains('f1'));
    });

    test(
      'sin red no cuenta como intento y espera con retroceso exponencial',
      () async {
        final _Entorno e = _Entorno();
        e.subidor.guion.addAll(<Object?>[_sinRed, _sinRed, _sinRed]);
        final ColaCaptura cola = await e.abrir();
        await cola.encolar(foto(1));

        expect(await cola.ronda(), const Duration(seconds: 2));
        expect(e.subidor.llamadas, 1);

        // Antes de tiempo no se intenta.
        e.reloj.avanzar(const Duration(seconds: 1));
        expect(await cola.ronda(), const Duration(seconds: 1));
        expect(e.subidor.llamadas, 1);

        e.reloj.avanzar(const Duration(seconds: 1));
        expect(await cola.ronda(), const Duration(seconds: 4));
        e.reloj.avanzar(const Duration(seconds: 4));
        expect(await cola.ronda(), const Duration(seconds: 8));
        e.reloj.avanzar(const Duration(seconds: 8));
        expect(await cola.ronda(), isNull);

        expect(e.subidor.llamadas, 4);
        expect(e.subidor.subidos, <String>['f1']);
        // Cuatro viajes sin red no la volvieron fallida.
        expect(cola.items, isEmpty);
      },
    );

    test(
      'sin red no se vuelve fallida por muchos que sean los fallos',
      () async {
        final _Entorno e = _Entorno();
        e.subidor.guion.addAll(<Object?>[for (int i = 0; i < 20; i++) _sinRed]);
        final ColaCaptura cola = await e.abrir(
          configuracion: const ConfiguracionCola(maxIntentos: 3),
        );
        await cola.encolar(foto(1));

        for (int i = 0; i < 20; i++) {
          await cola.ronda();
          e.reloj.avanzar(const Duration(minutes: 10));
        }

        expect(_item(cola, 'f1').estado, EstadoItem.porSubir);
        expect(_item(cola, 'f1').intentos, 0);
      },
    );

    test('una subida buena reinicia el retroceso', () async {
      final _Entorno e = _Entorno();
      e.subidor.guion.add(_sinRed);
      final ColaCaptura cola = await e.abrir();
      await cola.encolar(foto(1));
      expect(await cola.ronda(), const Duration(seconds: 2));
      e.reloj.avanzar(const Duration(seconds: 2));
      expect(await cola.ronda(), isNull); // subio bien

      await cola.encolar(foto(2));
      e.subidor.guion.add(_sinRed);

      // Vuelve a 2 s, no sigue por 4 s.
      expect(await cola.ronda(), const Duration(seconds: 2));
    });

    test(
      'si falta el PNG pero esta la original, se vuelve a procesar',
      () async {
        final _Entorno e = _Entorno();
        e.subidor.guion.add(_sinRed);
        final ColaCaptura cola = await e.abrir();
        await cola.encolar(foto(1));
        await cola.ronda();
        e.almacen.procesadas.remove('f1');
        e.reloj.avanzar(const Duration(seconds: 2));

        expect(await cola.ronda(), Duration.zero);
        expect(_item(cola, 'f1').estado, EstadoItem.porProcesar);

        expect(await cola.ronda(), isNull);
        expect(e.procesador.lotes, <int>[1, 1]);
        expect(e.subidor.subidos, <String>['f1']);
      },
    );

    test('el retroceso tiene tope y arranca en la espera base', () {
      const ConfiguracionCola c = ConfiguracionCola();
      expect(c.retroceso(0), Duration.zero);
      expect(c.retroceso(1), const Duration(seconds: 2));
      expect(c.retroceso(2), const Duration(seconds: 4));
      expect(c.retroceso(3), const Duration(seconds: 8));
      expect(c.retroceso(40), const Duration(minutes: 5));
    });
  });

  group('calor', () {
    test(
      'con el telefono caliente no se procesa, pero la subida sigue',
      () async {
        final _Entorno e = _Entorno();
        e.subidor.guion.add(_sinRed);
        final ColaCaptura cola = await e.abrir();
        await cola.encolar(foto(1));
        await cola.encolar(foto(2));
        await cola.ronda(); // procesa las dos; la subida espera por la red
        await cola.encolar(foto(3));
        e.termico.caliente = true;
        e.reloj.avanzar(const Duration(seconds: 2));

        final Duration? espera = await cola.ronda();

        expect(espera, const ConfiguracionCola().pausaTermica);
        expect(e.procesador.lotes, <int>[2]);
        expect(e.subidor.subidos, <String>['f1', 'f2']);
        expect(_item(cola, 'f3').estado, EstadoItem.porProcesar);

        e.termico.caliente = false;
        expect(await cola.ronda(), isNull);
        expect(e.procesador.lotes, <int>[2, 1]);
        expect(e.subidor.subidos, <String>['f1', 'f2', 'f3']);
      },
    );
  });

  group('persistencia', () {
    test('al reabrir sigue donde iba', () async {
      final _Entorno e = _Entorno();
      e.subidor.guion.add(_sinRed);
      final ColaCaptura primera = await e.abrir();
      await primera.encolar(foto(1));
      await primera.ronda(); // f1 queda por subir
      await primera.encolar(foto(2)); // f2 queda por procesar
      await primera.detener();

      final ColaCaptura segunda = await e.abrir();

      expect(_item(segunda, 'f1').estado, EstadoItem.porSubir);
      expect(_item(segunda, 'f1').datos!.categoriaColor, CategoriaColor.azul);
      expect(_item(segunda, 'f2').estado, EstadoItem.porProcesar);

      expect(await segunda.ronda(), isNull);
      expect(e.subidor.subidos, <String>['f1', 'f2']);
    });

    test('lo que estaba a medias de procesar se repite sin perder la foto', () async {
      final _Entorno e = _Entorno();
      // La app murio despues de guardar el PNG y antes de actualizar el indice.
      e.almacen.originales['f9'] = foto(9);
      e.almacen.procesadas['f9'] = Uint8List.fromList(<int>[0]);
      e.almacen.indice = <ItemCola>[
        ItemCola.nuevo(id: 'f9', creadoEn: e.reloj()),
      ];
      final ColaCaptura cola = await e.abrir();

      expect(await cola.ronda(), isNull);

      expect(e.subidor.subidos, <String>['f9']);
    });

    test('el indice y los items salen y entran del JSON iguales', () {
      final ItemCola original =
          ItemCola.nuevo(id: 'f1', creadoEn: DateTime.utc(2026, 10, 26, 8))
              .procesado(DatosPrenda.dePrenda(prendaDeEjemplo()))
              .conFallo(
                ahora: DateTime.utc(2026, 10, 26, 9),
                error: 'algo',
                definitivo: false,
              );

      final ItemCola vuelto = ItemCola.fromJson(original.toJson());

      expect(vuelto.id, original.id);
      expect(vuelto.estado, original.estado);
      expect(vuelto.intentos, 1);
      expect(vuelto.ultimoIntento, original.ultimoIntento);
      expect(vuelto.ultimoError, 'algo');
      expect(vuelto.creadoEn, original.creadoEn);
      expect(vuelto.datos!.tipo, TipoPrenda.camiseta);
      expect(vuelto.datos!.color.l, 50);
      expect(vuelto.datos!.color.b, -20);
    });
  });

  group('en segundo plano', () {
    test('encolar arranca el trabajo y reposo espera a que se vacie', () async {
      final _Entorno e = _Entorno();
      final ColaCaptura cola = await e.abrir(automatica: true);

      for (int i = 1; i <= 7; i++) {
        await cola.encolar(foto(i));
      }
      await cola.reposo();

      expect(e.subidor.subidos.toSet(), <String>{
        for (int i = 1; i <= 7; i++) 'f$i',
      });
      expect(cola.items, isEmpty);
      // Ningun lote paso del tamano configurado.
      expect(e.procesador.lotes.every((int n) => n <= 5), isTrue);
      expect(e.procesador.lotes.fold<int>(0, (int a, int b) => a + b), 7);
    });

    test(
      'una foto encolada despues de vaciarse la cola tambien se procesa',
      () async {
        final _Entorno e = _Entorno();
        final ColaCaptura cola = await e.abrir(automatica: true);
        await cola.encolar(foto(1));
        await cola.reposo();
        expect(cola.items, isEmpty);

        await cola.encolar(foto(2));
        await cola.reposo();

        expect(e.subidor.subidos, <String>['f1', 'f2']);
      },
    );

    test('sin red espera con retroceso y se recupera sola', () async {
      final _Entorno e = _Entorno();
      e.subidor.guion.addAll(<Object?>[_sinRed, _sinRed, _sinRed]);
      final ColaCaptura cola = await e.abrir(automatica: true);

      await cola.encolar(foto(1));
      await cola.reposo();

      expect(e.esperas, <Duration>[
        const Duration(seconds: 2),
        const Duration(seconds: 4),
        const Duration(seconds: 8),
      ]);
      expect(e.subidor.subidos, <String>['f1']);
    });

    test('detener corta una espera larga y deja la foto guardada', () async {
      final _Entorno e = _Entorno();
      e.subidor.guion.addAll(<Object?>[for (int i = 0; i < 50; i++) _sinRed]);
      // Una espera que no termina nunca por si sola.
      final ColaCaptura cola = await e.abrir(
        automatica: true,
        esperar: (Duration _) => Completer<void>().future,
      );
      await cola.encolar(foto(1));
      for (int i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      await cola.detener().timeout(const Duration(seconds: 2));

      expect(e.almacen.indice.single.estado, EstadoItem.porSubir);
      expect(e.almacen.originales, contains('f1'));
    });
  });

  group('ProcesadorSobrePipeline', () {
    test('prepara una vez por lote, procesa cada foto y libera', () async {
      final _PipelineFalso pipeline = _PipelineFalso();
      final ProcesadorSobrePipeline procesador = ProcesadorSobrePipeline(
        pipeline,
      );

      final List<ResultadoPrenda> r = await procesador.procesarLote(<Uint8List>[
        foto(1),
        foto(2),
        foto(3),
      ]);

      expect(r.whereType<PrendaProcesada>(), hasLength(3));
      expect(pipeline.eventos, <String>[
        'preparar',
        'procesar',
        'procesar',
        'procesar',
        'liberar',
      ]);
    });

    test('una foto que falla no tumba a las demas y igual se libera', () async {
      final _PipelineFalso pipeline = _PipelineFalso()..fallaLaFoto = 2;
      final ProcesadorSobrePipeline procesador = ProcesadorSobrePipeline(
        pipeline,
      );

      final List<ResultadoPrenda> r = await procesador.procesarLote(<Uint8List>[
        foto(1),
        foto(2),
        foto(3),
      ]);

      expect(r[0], isA<PrendaProcesada>());
      expect(r[1], isA<PrendaFallida>());
      expect(r[2], isA<PrendaProcesada>());
      expect(pipeline.eventos.last, 'liberar');
    });

    test(
      'si no se puede preparar, todas fallan y no se procesa nada',
      () async {
        final _PipelineFalso pipeline = _PipelineFalso()..fallaPreparar = true;
        final ProcesadorSobrePipeline procesador = ProcesadorSobrePipeline(
          pipeline,
        );

        final List<ResultadoPrenda> r = await procesador.procesarLote(
          <Uint8List>[foto(1), foto(2)],
        );

        expect(r.whereType<PrendaFallida>(), hasLength(2));
        expect(pipeline.eventos, <String>['preparar']);
      },
    );

    test('que liberar falle no pierde lo ya procesado', () async {
      final _PipelineFalso pipeline = _PipelineFalso()..fallaLiberar = true;
      final ProcesadorSobrePipeline procesador = ProcesadorSobrePipeline(
        pipeline,
      );

      final List<ResultadoPrenda> r = await procesador.procesarLote(<Uint8List>[
        foto(1),
      ]);

      expect(r.single, isA<PrendaProcesada>());
    });
  });
}

class _PipelineFalso implements GarmentPipeline {
  final List<String> eventos = <String>[];
  int? fallaLaFoto;
  bool fallaPreparar = false;
  bool fallaLiberar = false;

  @override
  bool get disponible => true;

  @override
  Future<void> preparar() async {
    eventos.add('preparar');
    if (fallaPreparar) throw StateError('no hay modelos');
  }

  @override
  Future<PrendaClasificada> procesar(Uint8List foto) async {
    eventos.add('procesar');
    if (foto.first == fallaLaFoto) throw StateError('foto mala');
    return prendaDeEjemplo(marca: foto.first);
  }

  @override
  Future<void> liberar() async {
    eventos.add('liberar');
    if (fallaLiberar) throw StateError('no se pudo soltar');
  }
}
