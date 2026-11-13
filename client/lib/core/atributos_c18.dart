/// Los atributos de una prenda tal como los entiende el backend (respuestas C.18).
///
/// Son los que produce el clasificador on-device y los que valida el Closet del
/// Core. `vocabulario.dart` es otra cosa: el de las pantallas mock, que se
/// escribio antes de cerrar C.18 y todavia no coincide (tiene `jean`, `blusa`,
/// `lunares`...). Cuando las pantallas pasen a datos reales, deberian usar este.
///
/// [TipoC18.codigo] y compania son los nombres exactos del esquema de Mongo y
/// del API: es lo que se guarda en la cola y lo que se sube.
library;

enum TipoC18 {
  camisa('CAMISA'),
  camiseta('CAMISETA'),
  sueter('SUETER'),
  cardigan('CARDIGAN'),
  chaqueta('CHAQUETA'),
  abrigo('ABRIGO'),
  chaleco('CHALECO'),
  pantalon('PANTALON'),
  short('SHORT'),
  falda('FALDA'),
  vestido('VESTIDO'),
  enterizo('ENTERIZO'),
  calzado('CALZADO'),
  gafas('GAFAS'),
  sombrero('SOMBRERO'),
  accesorioCabello('ACCESORIO_CABELLO'),
  corbata('CORBATA'),
  bufanda('BUFANDA'),
  reloj('RELOJ'),
  cinturon('CINTURON'),
  bolso('BOLSO'),

  /// No sale del clasificador: Fashionpedia no tiene joyeria. La pone el usuario.
  joyeria('JOYERIA');

  const TipoC18(this.codigo);

  final String codigo;

  static TipoC18 deCodigo(String codigo) => values.firstWhere(
    (TipoC18 t) => t.codigo == codigo,
    orElse: () => throw FormatException('Tipo desconocido: $codigo'),
  );
}

enum PatronC18 {
  liso('LISO'),
  rayas('RAYAS'),
  cuadros('CUADROS'),
  puntos('PUNTOS'),
  floral('FLORAL'),
  animal('ANIMAL'),
  geometrico('GEOMETRICO'),
  otroEstampado('OTRO_ESTAMPADO');

  const PatronC18(this.codigo);

  final String codigo;

  static PatronC18 deCodigo(String codigo) => values.firstWhere(
    (PatronC18 p) => p.codigo == codigo,
    orElse: () => throw FormatException('Patron desconocido: $codigo'),
  );
}

/// Sin clasificador en el MVP: sale por defecto del tipo o la elige el usuario
/// en la pantalla de revision (#55).
enum TexturaC18 {
  lisoLigero('LISO_LIGERO'),
  denim('DENIM'),
  punto('PUNTO'),
  pano('PANO'),
  cuero('CUERO'),
  satin('SATIN'),
  lino('LINO'),
  deportivo('DEPORTIVO'),
  acolchado('ACOLCHADO'),
  otra('OTRA');

  const TexturaC18(this.codigo);

  final String codigo;

  static TexturaC18 deCodigo(String codigo) => values.firstWhere(
    (TexturaC18 t) => t.codigo == codigo,
    orElse: () => throw FormatException('Textura desconocida: $codigo'),
  );
}
