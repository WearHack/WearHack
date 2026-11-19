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

/// Las 20 categorias de color de prenda, las mismas y en el mismo orden que
/// `CategoriaColor` del Core (#58), mas [multicolor].
///
/// Las asigna la tabla ISCC-NBS (`core/color/categoria_color.dart`).
/// [multicolor] no sale de la tabla: no es un color sino un patron, y lo decide
/// quien ve el patron. El Core no la tiene todavia.
enum CategoriaColor {
  negro,
  blanco,
  gris,
  beige,
  cafe,
  vinotinto,
  rojo,
  rosado,
  fucsia,
  naranja,
  amarillo,
  mostaza,
  verdeOliva,
  verde,
  turquesa,
  celeste,
  azul,
  azulMarino,
  morado,
  lila,
  multicolor;

  /// El nombre en el Core y en la tabla ISCC-NBS: `verdeOliva` es
  /// `VERDE_OLIVA`.
  String get codigo => name
      .replaceAllMapped(RegExp('[A-Z]'), (Match m) => '_${m[0]}')
      .toUpperCase();

  /// La categoria de un [codigo] del Core o de la tabla.
  static CategoriaColor desdeCodigo(String codigo) => values.firstWhere(
    (CategoriaColor c) => c.codigo == codigo,
    orElse: () =>
        throw FormatException('Categoria de color desconocida: $codigo'),
  );
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
