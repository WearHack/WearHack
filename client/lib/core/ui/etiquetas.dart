/// Como se muestra el vocabulario compartido con el backend.
///
/// El vocabulario (`TipoPrenda`, `Patron`, ...) lo fija el esquema de Mongo y no
/// cambia por gusto de la UI. Aqui solo se decide su texto, su icono y su color
/// en pantalla, en un solo sitio para que todas las vistas digan lo mismo.
library;

import 'package:flutter/material.dart';
import 'package:wearhack/core/vocabulario.dart';

extension EtiquetaTipoPrenda on TipoPrenda {
  String get etiqueta => switch (this) {
    TipoPrenda.camiseta => 'Camiseta',
    TipoPrenda.camisa => 'Camisa',
    TipoPrenda.blusa => 'Blusa',
    TipoPrenda.sueter => 'Suéter',
    TipoPrenda.chaqueta => 'Chaqueta',
    TipoPrenda.abrigo => 'Abrigo',
    TipoPrenda.pantalon => 'Pantalón',
    TipoPrenda.jean => 'Jean',
    TipoPrenda.falda => 'Falda',
    TipoPrenda.short => 'Short',
    TipoPrenda.vestido => 'Vestido',
    TipoPrenda.zapato => 'Zapatos',
    TipoPrenda.bota => 'Botas',
    TipoPrenda.tenis => 'Tenis',
    TipoPrenda.sandalia => 'Sandalias',
    TipoPrenda.accesorio => 'Accesorio',
  };
}

extension EtiquetaSlot on SlotOutfit {
  String get etiqueta => switch (this) {
    SlotOutfit.superior => 'Superior',
    SlotOutfit.inferior => 'Inferior',
    SlotOutfit.cuerpoEntero => 'Cuerpo entero',
    SlotOutfit.exterior => 'Exterior',
    SlotOutfit.calzado => 'Calzado',
    SlotOutfit.accesorio => 'Accesorio',
  };

  /// Icono del slot, para filtros y listas. La muestra de una prenda dibuja su
  /// propia silueta (`SiluetaPrenda`) y ya no lo usa.
  IconData get icono => switch (this) {
    SlotOutfit.superior => Icons.checkroom,
    SlotOutfit.inferior => Icons.accessibility_new,
    SlotOutfit.cuerpoEntero => Icons.woman,
    SlotOutfit.exterior => Icons.dry_cleaning,
    SlotOutfit.calzado => Icons.hiking,
    SlotOutfit.accesorio => Icons.watch,
  };
}

extension EtiquetaTextura on Textura {
  String get etiqueta => switch (this) {
    Textura.lisa => 'Lisa',
    Textura.punto => 'Punto',
    Textura.denim => 'Denim',
    Textura.cuero => 'Cuero',
    Textura.lana => 'Lana',
    Textura.lino => 'Lino',
    Textura.seda => 'Seda',
    Textura.algodon => 'Algodón',
    Textura.sintetico => 'Sintético',
  };
}

extension EtiquetaPatron on Patron {
  String get etiqueta => switch (this) {
    Patron.solido => 'Sólido',
    Patron.rayas => 'Rayas',
    Patron.cuadros => 'Cuadros',
    Patron.floral => 'Floral',
    Patron.lunares => 'Lunares',
    Patron.animal => 'Animal print',
    Patron.geometrico => 'Geométrico',
    Patron.estampado => 'Estampado',
  };
}

extension EtiquetaFormalidad on Formalidad {
  String get etiqueta => switch (this) {
    Formalidad.deportivo => 'Deportivo',
    Formalidad.casual => 'Casual',
    Formalidad.smartCasual => 'Smart casual',
    Formalidad.formal => 'Formal',
  };
}

extension EtiquetaClima on Clima {
  String get etiqueta => switch (this) {
    Clima.frio => 'Frío',
    Clima.templado => 'Templado',
    Clima.calido => 'Cálido',
    Clima.lluvia => 'Lluvia',
  };

  IconData get icono => switch (this) {
    Clima.frio => Icons.ac_unit,
    Clima.templado => Icons.filter_drama,
    Clima.calido => Icons.wb_sunny,
    Clima.lluvia => Icons.umbrella,
  };
}

extension EtiquetaCategoriaColor on CategoriaColor {
  String get etiqueta => switch (this) {
    CategoriaColor.blanco => 'Blanco',
    CategoriaColor.negro => 'Negro',
    CategoriaColor.gris => 'Gris',
    CategoriaColor.beige => 'Beige',
    CategoriaColor.marron => 'Marrón',
    CategoriaColor.rojo => 'Rojo',
    CategoriaColor.naranja => 'Naranja',
    CategoriaColor.amarillo => 'Amarillo',
    CategoriaColor.verde => 'Verde',
    CategoriaColor.azul => 'Azul',
    CategoriaColor.morado => 'Morado',
    CategoriaColor.rosa => 'Rosa',
    CategoriaColor.multicolor => 'Multicolor',
  };

  /// Un color representativo de la categoria, solo para pintar la muestra.
  ///
  /// No es el color real de la prenda: ese esta en Lab y convertirlo bien pide
  /// la cadena de `core/color/`. Para una miniatura basta con la categoria.
  Color get muestra => switch (this) {
    CategoriaColor.blanco => const Color(0xFFF5F5F5),
    CategoriaColor.negro => const Color(0xFF212121),
    CategoriaColor.gris => const Color(0xFF9E9E9E),
    CategoriaColor.beige => const Color(0xFFD7C4A3),
    CategoriaColor.marron => const Color(0xFF6D4C41),
    CategoriaColor.rojo => const Color(0xFFC62828),
    CategoriaColor.naranja => const Color(0xFFEF6C00),
    CategoriaColor.amarillo => const Color(0xFFF9A825),
    CategoriaColor.verde => const Color(0xFF2E7D32),
    CategoriaColor.azul => const Color(0xFF1565C0),
    CategoriaColor.morado => const Color(0xFF6A1B9A),
    CategoriaColor.rosa => const Color(0xFFF48FB1),
    CategoriaColor.multicolor => const Color(0xFF9575CD),
  };
}
