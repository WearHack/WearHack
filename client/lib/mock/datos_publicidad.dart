/// Marcas aliadas, su catalogo y las prendas puente de ejemplo.
///
/// Las marcas son inventadas a proposito: un mock con marcas reales pareceria
/// un acuerdo que no existe. Las combinaciones de ejemplo usan prendas del
/// closet de `datos_falsos.dart`, para que se vean coherentes con el.
library;

import 'package:wearhack/core/vocabulario.dart';
import 'package:wearhack/features/closet/prenda.dart';
import 'package:wearhack/features/outfits/contexto.dart';
import 'package:wearhack/features/outfits/outfit.dart';
import 'package:wearhack/features/publicidad/catalogo.dart';
import 'package:wearhack/mock/datos_falsos.dart';

const MarcaAliada _andes = MarcaAliada(
  id: 'm1',
  nombre: 'Andes Denim',
  descripcion: 'Denim y básicos de todos los días.',
);

const MarcaAliada _casaLino = MarcaAliada(
  id: 'm2',
  nombre: 'Casa Lino',
  descripcion: 'Lino y algodón para clima templado y cálido.',
);

const MarcaAliada _norte = MarcaAliada(
  id: 'm3',
  nombre: 'Norte Urbano',
  descripcion: 'Sastrería y básicos de oficina.',
);

const List<MarcaAliada> marcasDeEjemplo = <MarcaAliada>[
  _andes,
  _casaLino,
  _norte,
];

const ProductoCatalogo _blazer = ProductoCatalogo(
  id: 'c01',
  marca: _norte,
  nombre: 'Blazer negro de paño',
  precioPesos: 289900,
  prenda: Prenda(
    id: 'c01',
    tipo: TipoPrenda.chaqueta,
    slot: SlotOutfit.exterior,
    colorLab: ColorLab(l: 16.0, a: 0.0, b: 0.0),
    categoriaColor: CategoriaColor.negro,
    textura: Textura.lana,
    patron: Patron.solido,
    formalidad: Formalidad.formal,
    climaApto: <Clima>{Clima.frio, Clima.templado},
  ),
);

const ProductoCatalogo _camisaOxford = ProductoCatalogo(
  id: 'c02',
  marca: _norte,
  nombre: 'Camisa blanca Oxford',
  precioPesos: 129900,
  prenda: Prenda(
    id: 'c02',
    tipo: TipoPrenda.camisa,
    slot: SlotOutfit.superior,
    colorLab: ColorLab(l: 96.0, a: 0.0, b: 1.0),
    categoriaColor: CategoriaColor.blanco,
    textura: Textura.algodon,
    patron: Patron.solido,
    formalidad: Formalidad.formal,
    climaApto: <Clima>{Clima.frio, Clima.templado, Clima.calido},
  ),
);

const ProductoCatalogo _mocasines = ProductoCatalogo(
  id: 'c03',
  marca: _norte,
  nombre: 'Mocasines negros',
  precioPesos: 219900,
  prenda: Prenda(
    id: 'c03',
    tipo: TipoPrenda.zapato,
    slot: SlotOutfit.calzado,
    colorLab: ColorLab(l: 14.0, a: 0.0, b: 0.0),
    categoriaColor: CategoriaColor.negro,
    textura: Textura.cuero,
    patron: Patron.solido,
    formalidad: Formalidad.formal,
    climaApto: <Clima>{Clima.templado},
  ),
);

const ProductoCatalogo _pantalonLino = ProductoCatalogo(
  id: 'c04',
  marca: _casaLino,
  nombre: 'Pantalón de lino beige',
  precioPesos: 159900,
  prenda: Prenda(
    id: 'c04',
    tipo: TipoPrenda.pantalon,
    slot: SlotOutfit.inferior,
    colorLab: ColorLab(l: 78.0, a: 4.0, b: 16.0),
    categoriaColor: CategoriaColor.beige,
    textura: Textura.lino,
    patron: Patron.solido,
    formalidad: Formalidad.smartCasual,
    climaApto: <Clima>{Clima.templado, Clima.calido},
  ),
);

const ProductoCatalogo _vestidoCamisero = ProductoCatalogo(
  id: 'c05',
  marca: _casaLino,
  nombre: 'Vestido camisero verde',
  precioPesos: 199900,
  prenda: Prenda(
    id: 'c05',
    tipo: TipoPrenda.vestido,
    slot: SlotOutfit.cuerpoEntero,
    colorLab: ColorLab(l: 48.0, a: -28.0, b: 18.0),
    categoriaColor: CategoriaColor.verde,
    textura: Textura.lino,
    patron: Patron.solido,
    formalidad: Formalidad.smartCasual,
    climaApto: <Clima>{Clima.calido},
  ),
);

const ProductoCatalogo _sandalias = ProductoCatalogo(
  id: 'c06',
  marca: _casaLino,
  nombre: 'Sandalias de cuero',
  precioPesos: 139900,
  prenda: Prenda(
    id: 'c06',
    tipo: TipoPrenda.sandalia,
    slot: SlotOutfit.calzado,
    colorLab: ColorLab(l: 40.0, a: 14.0, b: 26.0),
    categoriaColor: CategoriaColor.marron,
    textura: Textura.cuero,
    patron: Patron.solido,
    formalidad: Formalidad.casual,
    climaApto: <Clima>{Clima.calido},
  ),
);

const ProductoCatalogo _chaquetaJean = ProductoCatalogo(
  id: 'c07',
  marca: _andes,
  nombre: 'Chaqueta de jean',
  precioPesos: 179900,
  prenda: Prenda(
    id: 'c07',
    tipo: TipoPrenda.chaqueta,
    slot: SlotOutfit.exterior,
    colorLab: ColorLab(l: 50.0, a: -2.0, b: -28.0),
    categoriaColor: CategoriaColor.azul,
    textura: Textura.denim,
    patron: Patron.solido,
    formalidad: Formalidad.casual,
    climaApto: <Clima>{Clima.frio, Clima.templado},
  ),
);

const ProductoCatalogo _jeanNegro = ProductoCatalogo(
  id: 'c08',
  marca: _andes,
  nombre: 'Jean negro recto',
  precioPesos: 149900,
  prenda: Prenda(
    id: 'c08',
    tipo: TipoPrenda.jean,
    slot: SlotOutfit.inferior,
    colorLab: ColorLab(l: 18.0, a: 0.0, b: -2.0),
    categoriaColor: CategoriaColor.negro,
    textura: Textura.denim,
    patron: Patron.solido,
    formalidad: Formalidad.casual,
    climaApto: <Clima>{Clima.frio, Clima.templado, Clima.calido},
  ),
);

const ProductoCatalogo _camisetaGris = ProductoCatalogo(
  id: 'c09',
  marca: _andes,
  nombre: 'Camiseta gris básica',
  precioPesos: 49900,
  prenda: Prenda(
    id: 'c09',
    tipo: TipoPrenda.camiseta,
    slot: SlotOutfit.superior,
    colorLab: ColorLab(l: 60.0, a: 0.0, b: 0.0),
    categoriaColor: CategoriaColor.gris,
    textura: Textura.algodon,
    patron: Patron.solido,
    formalidad: Formalidad.casual,
    climaApto: <Clima>{Clima.frio, Clima.templado, Clima.calido},
  ),
);

const List<ProductoCatalogo> catalogoDeEjemplo = <ProductoCatalogo>[
  _blazer,
  _camisaOxford,
  _mocasines,
  _pantalonLino,
  _vestidoCamisero,
  _sandalias,
  _chaquetaJean,
  _jeanNegro,
  _camisetaGris,
];

Prenda _delCloset(String id) =>
    prendasDeEjemplo.firstWhere((Prenda p) => p.id == id);

Outfit _combinacion(
  String id,
  Formalidad formalidad,
  Clima clima,
  Map<SlotOutfit, String> delCloset,
  ProductoCatalogo nueva,
) => Outfit(
  id: id,
  formalidad: formalidad,
  clima: clima,
  prendas: <SlotOutfit, Prenda>{
    for (final MapEntry<SlotOutfit, String> e in delCloset.entries)
      e.key: _delCloset(e.value),
    nueva.prenda.slot: nueva.prenda,
  },
);

/// El ranking que dejaria el job nocturno. Los numeros son inventados; el
/// orden si sigue las reglas de D.28: por combinaciones, y el empate a 7 lo
/// gana la que tendria menor costo promedio.
///
/// No es const porque las combinaciones se arman con las prendas del closet.
final List<PrendaPuente> prendasPuenteDeEjemplo = <PrendaPuente>[
  PrendaPuente(
    producto: _blazer,
    combinacionesBuenas: 9,
    // Ningun outfit de ejemplo es formal: hoy no puede ir a una boda.
    ocasionesNuevas: const <Ocasion>[Ocasion.formal],
    ejemplos: <Outfit>[
      _combinacion(
        'pp-c01-1',
        Formalidad.formal,
        Clima.templado,
        const <SlotOutfit, String>{
          SlotOutfit.superior: 'p02',
          SlotOutfit.inferior: 'p06',
          SlotOutfit.calzado: 'p14',
        },
        _blazer,
      ),
      _combinacion(
        'pp-c01-2',
        Formalidad.formal,
        Clima.templado,
        const <SlotOutfit, String>{
          SlotOutfit.superior: 'p03',
          SlotOutfit.inferior: 'p06',
          SlotOutfit.calzado: 'p14',
        },
        _blazer,
      ),
      _combinacion(
        'pp-c01-3',
        Formalidad.smartCasual,
        Clima.templado,
        const <SlotOutfit, String>{
          SlotOutfit.superior: 'p01',
          SlotOutfit.inferior: 'p05',
          SlotOutfit.calzado: 'p12',
        },
        _blazer,
      ),
    ],
  ),
  PrendaPuente(
    producto: _jeanNegro,
    combinacionesBuenas: 7,
    ocasionesNuevas: const <Ocasion>[],
    ejemplos: <Outfit>[
      _combinacion(
        'pp-c08-1',
        Formalidad.casual,
        Clima.templado,
        const <SlotOutfit, String>{
          SlotOutfit.superior: 'p01',
          SlotOutfit.calzado: 'p12',
        },
        _jeanNegro,
      ),
      _combinacion(
        'pp-c08-2',
        Formalidad.casual,
        Clima.frio,
        const <SlotOutfit, String>{
          SlotOutfit.superior: 'p04',
          SlotOutfit.exterior: 'p11',
          SlotOutfit.calzado: 'p13',
        },
        _jeanNegro,
      ),
      _combinacion(
        'pp-c08-3',
        Formalidad.smartCasual,
        Clima.templado,
        const <SlotOutfit, String>{
          SlotOutfit.superior: 'p02',
          SlotOutfit.calzado: 'p14',
        },
        _jeanNegro,
      ),
    ],
  ),
  PrendaPuente(
    producto: _pantalonLino,
    combinacionesBuenas: 7,
    ocasionesNuevas: const <Ocasion>[],
    ejemplos: <Outfit>[
      _combinacion(
        'pp-c04-1',
        Formalidad.casual,
        Clima.calido,
        const <SlotOutfit, String>{
          SlotOutfit.superior: 'p01',
          SlotOutfit.calzado: 'p12',
        },
        _pantalonLino,
      ),
      _combinacion(
        'pp-c04-2',
        Formalidad.smartCasual,
        Clima.templado,
        const <SlotOutfit, String>{
          SlotOutfit.superior: 'p03',
          SlotOutfit.calzado: 'p14',
        },
        _pantalonLino,
      ),
    ],
  ),
  PrendaPuente(
    producto: _chaquetaJean,
    combinacionesBuenas: 5,
    ocasionesNuevas: const <Ocasion>[],
    ejemplos: <Outfit>[
      _combinacion(
        'pp-c07-1',
        Formalidad.casual,
        Clima.templado,
        const <SlotOutfit, String>{
          SlotOutfit.superior: 'p01',
          SlotOutfit.inferior: 'p07',
          SlotOutfit.calzado: 'p12',
        },
        _chaquetaJean,
      ),
      _combinacion(
        'pp-c07-2',
        Formalidad.casual,
        Clima.templado,
        const <SlotOutfit, String>{
          SlotOutfit.cuerpoEntero: 'p09',
          SlotOutfit.calzado: 'p12',
        },
        _chaquetaJean,
      ),
    ],
  ),
  // Por debajo del umbral: el repositorio no debe devolverla.
  const PrendaPuente(
    producto: _mocasines,
    combinacionesBuenas: 3,
    ocasionesNuevas: <Ocasion>[],
    ejemplos: <Outfit>[],
  ),
];
