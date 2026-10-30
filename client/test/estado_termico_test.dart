import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wearhack/features/closet/captura/estado_termico.dart';

/// Un estado termico con streams que se controlan desde la prueba.
class _Sensores {
  final StreamController<NivelTermico> niveles =
      StreamController<NivelTermico>();
  final StreamController<double> bateria = StreamController<double>();

  EstadoTermicoDispositivo estado([
    UmbralTermico umbral = const UmbralTermico(),
  ]) => EstadoTermicoDispositivo(
    niveles: niveles.stream,
    temperaturasBateria: bateria.stream,
    umbral: umbral,
  );
}

void main() {
  test('sin ninguna lectura no esta caliente', () {
    expect(_Sensores().estado().caliente, isFalse);
  });

  test('el estado del sistema manda desde el nivel de pausa', () async {
    final _Sensores s = _Sensores();
    final EstadoTermicoDispositivo estado = s.estado();

    s.niveles.add(NivelTermico.moderado);
    await pumpEventQueue();
    expect(estado.caliente, isFalse);

    s.niveles.add(NivelTermico.severo);
    await pumpEventQueue();
    expect(estado.caliente, isTrue);

    s.niveles.add(NivelTermico.leve);
    await pumpEventQueue();
    expect(estado.caliente, isFalse);
  });

  test('con estado del sistema, la bateria no cuenta', () async {
    final _Sensores s = _Sensores();
    final EstadoTermicoDispositivo estado = s.estado();

    s.niveles.add(NivelTermico.leve);
    s.bateria.add(50);
    await pumpEventQueue();
    expect(estado.caliente, isFalse);
  });

  test('sin estado del sistema (Android 8 y 9) decide la bateria', () async {
    final _Sensores s = _Sensores();
    final EstadoTermicoDispositivo estado = s.estado();

    // Los equipos sin soporte reportan "ninguno".
    s.niveles.add(NivelTermico.ninguno);
    s.bateria.add(41.9);
    await pumpEventQueue();
    expect(estado.caliente, isFalse);

    s.bateria.add(42);
    await pumpEventQueue();
    expect(estado.caliente, isTrue);
  });

  test('un sensor que falla deja de contar', () async {
    final _Sensores s = _Sensores();
    final EstadoTermicoDispositivo estado = s.estado();

    s.bateria.add(45);
    await pumpEventQueue();
    expect(estado.caliente, isTrue);

    s.bateria.addError(StateError('sin sensor'));
    await pumpEventQueue();
    expect(estado.caliente, isFalse);
  });

  test('los umbrales se leen de texto y lo invalido vale el provisional', () {
    final UmbralTermico leido = UmbralTermico.desdeTextos(
      nivel: ' Moderado ',
      bateria: '40',
    );
    expect(leido.nivelDePausa, NivelTermico.moderado);
    expect(leido.bateriaMaximaC, 40);

    final UmbralTermico invalido = UmbralTermico.desdeTextos(
      nivel: 'tibio',
      bateria: 'mucho',
    );
    expect(invalido.nivelDePausa, NivelTermico.severo);
    expect(invalido.bateriaMaximaC, 42);
  });

  test('un umbral mas estricto pausa antes', () async {
    final _Sensores s = _Sensores();
    final EstadoTermicoDispositivo estado = s.estado(
      const UmbralTermico(nivelDePausa: NivelTermico.moderado),
    );

    s.niveles.add(NivelTermico.moderado);
    await pumpEventQueue();
    expect(estado.caliente, isTrue);
  });
}
