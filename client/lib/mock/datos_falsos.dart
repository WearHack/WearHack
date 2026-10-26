/// Un closet de ejemplo para maquetar las pantallas sin backend.
///
/// Todo respeta el vocabulario y el esquema de Mongo, para que cambiar el
/// repositorio falso por el real no destape datos que el backend rechazaria.
library;

import 'package:wearhack/core/vocabulario.dart';
import 'package:wearhack/features/closet/prenda.dart';
import 'package:wearhack/features/outfits/outfit.dart';

const Prenda _camisetaBlanca = Prenda(
  id: 'p01',
  tipo: TipoPrenda.camiseta,
  slot: SlotOutfit.superior,
  colorLab: ColorLab(l: 95.0, a: 0.0, b: 2.0),
  categoriaColor: CategoriaColor.blanco,
  textura: Textura.algodon,
  patron: Patron.solido,
  formalidad: Formalidad.casual,
  climaApto: <Clima>{Clima.templado, Clima.calido},
);

const Prenda _camisaRayas = Prenda(
  id: 'p02',
  tipo: TipoPrenda.camisa,
  slot: SlotOutfit.superior,
  colorLab: ColorLab(l: 55.0, a: -5.0, b: -35.0),
  categoriaColor: CategoriaColor.azul,
  textura: Textura.algodon,
  patron: Patron.rayas,
  formalidad: Formalidad.smartCasual,
  climaApto: <Clima>{Clima.templado, Clima.calido},
);

const Prenda _blusaRosa = Prenda(
  id: 'p03',
  tipo: TipoPrenda.blusa,
  slot: SlotOutfit.superior,
  colorLab: ColorLab(l: 80.0, a: 20.0, b: 5.0),
  categoriaColor: CategoriaColor.rosa,
  textura: Textura.seda,
  patron: Patron.solido,
  formalidad: Formalidad.formal,
  climaApto: <Clima>{Clima.templado},
);

const Prenda _sueterBeige = Prenda(
  id: 'p04',
  tipo: TipoPrenda.sueter,
  slot: SlotOutfit.superior,
  colorLab: ColorLab(l: 80.0, a: 3.0, b: 15.0),
  categoriaColor: CategoriaColor.beige,
  textura: Textura.lana,
  patron: Patron.solido,
  formalidad: Formalidad.casual,
  climaApto: <Clima>{Clima.frio},
);

const Prenda _jeanAzul = Prenda(
  id: 'p05',
  tipo: TipoPrenda.jean,
  slot: SlotOutfit.inferior,
  colorLab: ColorLab(l: 35.0, a: 0.0, b: -25.0),
  categoriaColor: CategoriaColor.azul,
  textura: Textura.denim,
  patron: Patron.solido,
  formalidad: Formalidad.casual,
  climaApto: <Clima>{Clima.frio, Clima.templado, Clima.calido},
);

const Prenda _pantalonNegro = Prenda(
  id: 'p06',
  tipo: TipoPrenda.pantalon,
  slot: SlotOutfit.inferior,
  colorLab: ColorLab(l: 15.0, a: 0.0, b: 0.0),
  categoriaColor: CategoriaColor.negro,
  textura: Textura.sintetico,
  patron: Patron.solido,
  formalidad: Formalidad.formal,
  climaApto: <Clima>{Clima.frio, Clima.templado},
);

const Prenda _faldaVerde = Prenda(
  id: 'p07',
  tipo: TipoPrenda.falda,
  slot: SlotOutfit.inferior,
  colorLab: ColorLab(l: 50.0, a: -30.0, b: 20.0),
  categoriaColor: CategoriaColor.verde,
  textura: Textura.lino,
  patron: Patron.solido,
  formalidad: Formalidad.smartCasual,
  climaApto: <Clima>{Clima.calido},
);

const Prenda _shortBeige = Prenda(
  id: 'p08',
  tipo: TipoPrenda.short,
  slot: SlotOutfit.inferior,
  colorLab: ColorLab(l: 75.0, a: 5.0, b: 20.0),
  categoriaColor: CategoriaColor.beige,
  textura: Textura.algodon,
  patron: Patron.solido,
  formalidad: Formalidad.deportivo,
  climaApto: <Clima>{Clima.calido},
);

const Prenda _vestidoFloral = Prenda(
  id: 'p09',
  tipo: TipoPrenda.vestido,
  slot: SlotOutfit.cuerpoEntero,
  colorLab: ColorLab(l: 45.0, a: 55.0, b: 35.0),
  categoriaColor: CategoriaColor.rojo,
  textura: Textura.algodon,
  patron: Patron.floral,
  formalidad: Formalidad.casual,
  climaApto: <Clima>{Clima.calido},
);

const Prenda _chaquetaCuero = Prenda(
  id: 'p10',
  tipo: TipoPrenda.chaqueta,
  slot: SlotOutfit.exterior,
  colorLab: ColorLab(l: 35.0, a: 15.0, b: 25.0),
  categoriaColor: CategoriaColor.marron,
  textura: Textura.cuero,
  patron: Patron.solido,
  formalidad: Formalidad.smartCasual,
  climaApto: <Clima>{Clima.frio, Clima.templado},
);

const Prenda _abrigoGris = Prenda(
  id: 'p11',
  tipo: TipoPrenda.abrigo,
  slot: SlotOutfit.exterior,
  colorLab: ColorLab(l: 55.0, a: 0.0, b: 0.0),
  categoriaColor: CategoriaColor.gris,
  textura: Textura.lana,
  patron: Patron.solido,
  formalidad: Formalidad.formal,
  climaApto: <Clima>{Clima.frio, Clima.lluvia},
);

const Prenda _tenisBlancos = Prenda(
  id: 'p12',
  tipo: TipoPrenda.tenis,
  slot: SlotOutfit.calzado,
  colorLab: ColorLab(l: 92.0, a: 0.0, b: 0.0),
  categoriaColor: CategoriaColor.blanco,
  textura: Textura.sintetico,
  patron: Patron.solido,
  formalidad: Formalidad.deportivo,
  climaApto: <Clima>{Clima.templado, Clima.calido},
);

const Prenda _botasNegras = Prenda(
  id: 'p13',
  tipo: TipoPrenda.bota,
  slot: SlotOutfit.calzado,
  colorLab: ColorLab(l: 18.0, a: 0.0, b: 0.0),
  categoriaColor: CategoriaColor.negro,
  textura: Textura.cuero,
  patron: Patron.solido,
  formalidad: Formalidad.casual,
  climaApto: <Clima>{Clima.frio, Clima.lluvia},
);

const Prenda _zapatosMarron = Prenda(
  id: 'p14',
  tipo: TipoPrenda.zapato,
  slot: SlotOutfit.calzado,
  colorLab: ColorLab(l: 30.0, a: 12.0, b: 20.0),
  categoriaColor: CategoriaColor.marron,
  textura: Textura.cuero,
  patron: Patron.solido,
  formalidad: Formalidad.formal,
  climaApto: <Clima>{Clima.templado},
);

const Prenda _bufandaCuadros = Prenda(
  id: 'p15',
  tipo: TipoPrenda.accesorio,
  slot: SlotOutfit.accesorio,
  colorLab: ColorLab(l: 50.0, a: 25.0, b: 10.0),
  categoriaColor: CategoriaColor.multicolor,
  textura: Textura.lana,
  patron: Patron.cuadros,
  formalidad: Formalidad.casual,
  climaApto: <Clima>{Clima.frio},
);

const List<Prenda> prendasDeEjemplo = <Prenda>[
  _camisetaBlanca,
  _camisaRayas,
  _blusaRosa,
  _sueterBeige,
  _jeanAzul,
  _pantalonNegro,
  _faldaVerde,
  _shortBeige,
  _vestidoFloral,
  _chaquetaCuero,
  _abrigoGris,
  _tenisBlancos,
  _botasNegras,
  _zapatosMarron,
  _bufandaCuadros,
];

const List<Outfit> outfitsDeEjemplo = <Outfit>[
  Outfit(
    id: 'o1',
    formalidad: Formalidad.casual,
    clima: Clima.templado,
    prendas: <SlotOutfit, Prenda>{
      SlotOutfit.superior: _camisetaBlanca,
      SlotOutfit.inferior: _jeanAzul,
      SlotOutfit.calzado: _tenisBlancos,
    },
  ),
  Outfit(
    id: 'o2',
    formalidad: Formalidad.smartCasual,
    clima: Clima.templado,
    prendas: <SlotOutfit, Prenda>{
      SlotOutfit.superior: _camisaRayas,
      SlotOutfit.inferior: _pantalonNegro,
      SlotOutfit.exterior: _chaquetaCuero,
      SlotOutfit.calzado: _zapatosMarron,
    },
  ),
  Outfit(
    id: 'o3',
    formalidad: Formalidad.casual,
    clima: Clima.calido,
    prendas: <SlotOutfit, Prenda>{
      SlotOutfit.cuerpoEntero: _vestidoFloral,
      SlotOutfit.calzado: _tenisBlancos,
    },
  ),
  Outfit(
    id: 'o4',
    formalidad: Formalidad.casual,
    clima: Clima.frio,
    prendas: <SlotOutfit, Prenda>{
      SlotOutfit.superior: _sueterBeige,
      SlotOutfit.inferior: _jeanAzul,
      SlotOutfit.exterior: _abrigoGris,
      SlotOutfit.calzado: _botasNegras,
      SlotOutfit.accesorio: _bufandaCuadros,
    },
  ),
  Outfit(
    id: 'o5',
    formalidad: Formalidad.smartCasual,
    clima: Clima.calido,
    prendas: <SlotOutfit, Prenda>{
      SlotOutfit.superior: _blusaRosa,
      SlotOutfit.inferior: _faldaVerde,
      SlotOutfit.calzado: _zapatosMarron,
    },
  ),
];

/// En que orden el mock ofrece candidatas para elegir el mejor de N. El motor
/// real ordena por costo y diversidad (respuestas D.27); aqui basta un orden
/// fijo. Los tres primeros se diferencian en al menos dos prendas principales.
const List<String> candidatasDeEjemplo = <String>['o1', 'o3', 'o5', 'o2', 'o4'];

/// El outfit de cada dia, de lunes a domingo. `null` es un dia libre.
const List<String?> planDeEjemplo = <String?>[
  'o1',
  'o2',
  null,
  'o4',
  'o3',
  'o5',
  null,
];
