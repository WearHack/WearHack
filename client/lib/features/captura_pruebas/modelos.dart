/// Vocabulario de la sesion de captura de pruebas (calibracion de colorimetria).
///
/// Los codigos son los de `docs/protocolo-normalizacion-colorimetria.md` (3.2) y
/// `docs/spec-modo-captura-pruebas.md` (3.3). Una toma se identifica por
/// persona, luz, celular y repeticion, y de ahi sale el nombre de sus archivos.
library;

/// Condicion de luz de la toma.
enum Luz {
  /// Ventana, luz indirecta.
  ven('VEN'),

  /// LED calido (bombilla amarilla).
  ledc('LEDC'),

  /// LED o fluorescente frio (oficina).
  ledf('LEDF'),

  /// Ventana mas bombilla.
  mix('MIX'),

  /// Poca luz (una lampara de noche).
  baj('BAJ');

  const Luz(this.codigo);

  final String codigo;

  static Luz? desdeCodigo(String codigo) {
    for (final Luz l in Luz.values) {
      if (l.codigo == codigo) return l;
    }
    return null;
  }
}

/// Numero de repeticion. Solo `R1` lleva la tarjeta gris en el encuadre.
enum Repeticion {
  r1('R1'),
  r2('R2'),
  r3('R3');

  const Repeticion(this.codigo);

  final String codigo;

  /// La tarjeta gris va solo en la primera repeticion: un objeto gris en la
  /// escena ayuda al balance automatico del celular, y si estuviera en todas
  /// las fotos la linea base saldria mejor de lo que es en uso real.
  bool get llevaTarjetaGris => this == Repeticion.r1;

  /// `G` con tarjeta, `N` sin ella.
  String get marcaTarjeta => llevaTarjetaGris ? 'G' : 'N';

  static Repeticion? desdeCodigo(String codigo) {
    for (final Repeticion r in Repeticion.values) {
      if (r.codigo == codigo) return r;
    }
    return null;
  }
}

/// Codigo del celular de la sesion.
enum CodigoCelular {
  d1('D1', 'iPhone'),
  d2('D2', 'Android gama baja'),

  /// El reservado para la validacion final: no se usa para desarrollar.
  d3('D3', 'Android gama media');

  const CodigoCelular(this.codigo, this.descripcion);

  final String codigo;
  final String descripcion;

  static CodigoCelular? desdeCodigo(String codigo) {
    for (final CodigoCelular c in CodigoCelular.values) {
      if (c.codigo == codigo) return c;
    }
    return null;
  }
}

/// Seudonimo de una persona del equipo: `P1` a `P6`. Nunca un nombre real.
class Seudonimo {
  /// Lanza [ArgumentError] si no es `P1` a `P6` exactamente.
  factory Seudonimo(String valor) {
    if (!_formato.hasMatch(valor)) {
      throw ArgumentError.value(valor, 'valor', 'Debe ser P1 a P6');
    }
    return Seudonimo._(valor);
  }

  const Seudonimo._(this.valor);

  static final RegExp _formato = RegExp(r'^P[1-6]$');

  static bool esValido(String valor) => _formato.hasMatch(valor);

  final String valor;

  @override
  bool operator ==(Object other) => other is Seudonimo && other.valor == valor;

  @override
  int get hashCode => valor.hashCode;

  @override
  String toString() => valor;
}

/// Identifica una toma: persona, luz, celular y repeticion.
class IdToma {
  const IdToma({
    required this.seudonimo,
    required this.luz,
    required this.celular,
    required this.repeticion,
  });

  final Seudonimo seudonimo;
  final Luz luz;
  final CodigoCelular celular;
  final Repeticion repeticion;

  bool get tarjetaGris => repeticion.llevaTarjetaGris;

  /// Base de los nombres de archivo, por ejemplo `P3_LEDC_D2_R1_G`.
  String get nombreBase =>
      '${seudonimo.valor}_${luz.codigo}_${celular.codigo}_'
      '${repeticion.codigo}_${repeticion.marcaTarjeta}';

  /// Lee un nombre base. Devuelve `null` si no tiene la forma exacta o si la
  /// marca de tarjeta no corresponde a la repeticion.
  static IdToma? desdeNombreBase(String nombre) {
    final List<String> partes = nombre.split('_');
    if (partes.length != 5) return null;
    if (!Seudonimo.esValido(partes[0])) return null;
    final Luz? luz = Luz.desdeCodigo(partes[1]);
    final CodigoCelular? celular = CodigoCelular.desdeCodigo(partes[2]);
    final Repeticion? repeticion = Repeticion.desdeCodigo(partes[3]);
    if (luz == null || celular == null || repeticion == null) return null;
    if (partes[4] != repeticion.marcaTarjeta) return null;
    return IdToma(
      seudonimo: Seudonimo(partes[0]),
      luz: luz,
      celular: celular,
      repeticion: repeticion,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is IdToma && other.nombreBase == nombreBase;

  @override
  int get hashCode => nombreBase.hashCode;

  @override
  String toString() => nombreBase;
}
