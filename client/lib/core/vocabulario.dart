/// Vocabulario compartido con el backend.
///
/// Estos valores son los mismos que valida el `$jsonSchema` de la coleccion
/// `prendas` en MongoDB (ver `infra/local/mongo/init/01-colecciones.js`). El
/// modelo on-device produce estos nombres y la base los rechaza si no cuadran,
/// asi que si cambian, cambian en los dos sitios.
library;

enum TipoPrenda {
  camiseta,
  camisa,
  blusa,
  sueter,
  chaqueta,
  abrigo,
  pantalon,
  jean,
  falda,
  short,
  vestido,
  zapato,
  bota,
  tenis,
  sandalia,
  accesorio,
}

enum Textura { lisa, punto, denim, cuero, lana, lino, seda, algodon, sintetico }

enum Patron {
  solido,
  rayas,
  cuadros,
  floral,
  lunares,
  animal,
  geometrico,
  estampado,
}

enum Formalidad { deportivo, casual, smartCasual, formal }

/// Un outfit se arma llenando slots. Un slot vacio es un hueco, no un error.
enum SlotOutfit {
  superior,
  inferior,
  cuerpoEntero,
  exterior,
  calzado,
  accesorio,
}

enum Clima { frio, templado, calido, lluvia }

enum CategoriaColor {
  blanco,
  negro,
  gris,
  beige,
  marron,
  rojo,
  naranja,
  amarillo,
  verde,
  azul,
  morado,
  rosa,
  multicolor,
}

/// Color en espacio CIELAB.
///
/// Lab y no RGB porque aqui la distancia entre dos colores se parece a la
/// diferencia que percibe el ojo, que es lo que necesita la colorimetria por
/// nearest-centroid. En RGB dos colores igual de separados numericamente
/// pueden verse identicos o completamente distintos.
class ColorLab {
  const ColorLab({required this.l, required this.a, required this.b});

  /// Luminosidad, de 0 (negro) a 100 (blanco).
  final double l;

  /// Eje verde-rojo, de -128 a 127.
  final double a;

  /// Eje azul-amarillo, de -128 a 127.
  final double b;

  @override
  String toString() => 'ColorLab($l, $a, $b)';
}
