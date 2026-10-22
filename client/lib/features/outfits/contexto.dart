/// Para que se genera un outfit: la ocasion, el mood y el clima.
///
/// Es el `contexto` del cuerpo de `POST /v1/recomendacion/generar` (protocolos,
/// seccion 7). La ocasion y el clima son filtros duros que aplica el Core; el
/// mood es un termino suave del score que aplica el motor.
library;

import 'package:wearhack/core/vocabulario.dart';

/// El dress code. Cada ocasion admite un rango de formalidad (respuestas D.24).
enum Ocasion {
  deporte(Formalidad.deportivo, Formalidad.deportivo),
  diaADia(Formalidad.deportivo, Formalidad.smartCasual),
  salidaCasual(Formalidad.casual, Formalidad.smartCasual),
  oficina(Formalidad.smartCasual, Formalidad.formal),
  entrevista(Formalidad.smartCasual, Formalidad.formal),
  cenaElegante(Formalidad.smartCasual, Formalidad.formal),
  formal(Formalidad.formal, Formalidad.formal);

  const Ocasion(this.formalidadMinima, this.formalidadMaxima);

  final Formalidad formalidadMinima;
  final Formalidad formalidadMaxima;

  bool admite(Formalidad f) =>
      f.index >= formalidadMinima.index && f.index <= formalidadMaxima.index;

  String get etiqueta => switch (this) {
    Ocasion.deporte => 'Deporte',
    Ocasion.diaADia => 'Día a día',
    Ocasion.salidaCasual => 'Salida casual',
    Ocasion.oficina => 'Oficina',
    Ocasion.entrevista => 'Entrevista',
    Ocasion.cenaElegante => 'Cena elegante',
    Ocasion.formal => 'Formal',
  };

  /// Ejemplos, tal como los da D.24, para que el usuario sepa cual elegir.
  String get ejemplos => switch (this) {
    Ocasion.deporte => 'Gimnasio, correr',
    Ocasion.diaADia => 'Casa, universidad, diligencias',
    Ocasion.salidaCasual => 'Amigos, cine, fiesta',
    Ocasion.oficina => 'Trabajo, presentación',
    Ocasion.entrevista => 'Entrevista de trabajo',
    Ocasion.cenaElegante => 'Cena, evento nocturno',
    Ocasion.formal => 'Boda, gala, grado',
  };
}

/// Opcional. Ajusta el score dentro de lo que la ocasion ya permite
/// (respuestas D.25); no filtra nada.
enum Mood {
  relajado,
  elegante,
  atrevido,
  discreto;

  String get etiqueta => switch (this) {
    Mood.relajado => 'Relajado',
    Mood.elegante => 'Elegante',
    Mood.atrevido => 'Atrevido',
    Mood.discreto => 'Discreto',
  };
}

/// Por debajo de esto es frio (respuestas C.18).
const double limiteFrio = 14;

/// Por encima de esto es calido (respuestas C.18).
const double limiteCalido = 22;

/// La banda de clima de una temperatura en grados Celsius.
///
/// Las bandas viven en `configuracion` y son configurables; estos valores son
/// los iniciales. Nunca devuelve [Clima.lluvia]: la lluvia queda fuera del MVP.
Clima climaPara(double celsius) {
  if (celsius < limiteFrio) return Clima.frio;
  if (celsius > limiteCalido) return Clima.calido;
  return Clima.templado;
}

class ContextoOutfit {
  const ContextoOutfit({this.ocasion = Ocasion.diaADia, this.mood, this.clima});

  final Ocasion ocasion;
  final Mood? mood;

  /// `null` es "sin dato de clima": el motor lo soporta sin caso especial.
  final Clima? clima;

  ContextoOutfit conOcasion(Ocasion ocasion) =>
      ContextoOutfit(ocasion: ocasion, mood: mood, clima: clima);

  ContextoOutfit conMood(Mood? mood) =>
      ContextoOutfit(ocasion: ocasion, mood: mood, clima: clima);

  ContextoOutfit conClima(Clima? clima) =>
      ContextoOutfit(ocasion: ocasion, mood: mood, clima: clima);

  /// Identifica el contexto, para distinguir lotes generados con distinto.
  String get clave =>
      '${ocasion.name}.${mood?.name ?? '-'}.${clima?.name ?? '-'}';
}
