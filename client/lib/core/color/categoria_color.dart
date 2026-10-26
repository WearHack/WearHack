/// De un color en Lab a la categoria de color del vocabulario.
///
/// **Las fronteras son provisionales.** El vocabulario sale de las categorias de
/// ISCC-NBS, pero no hay todavia una tabla de calibracion: estos cortes por
/// luminosidad, croma y matiz se ajustaron a mano contra unos 40 colores de
/// referencia (blancos, grises, rojos, azules, el beige, el marron...) y tienen
/// zonas dudosas en los bordes, sobre todo entre azul y morado (matiz ~310) y
/// entre naranja y marron. Cuando haya datos reales de prendas, se recalibra
/// aqui y en ningun otro sitio.
///
/// **No devuelve `multicolor`.** Eso no es una propiedad de un color sino de la
/// prenda (un patron con varios colores), y lo decide quien ve el patron.
library;

import 'dart:math' as math;

import 'package:wearhack/core/vocabulario.dart';

CategoriaColor categoriaDeLab(ColorLab color) {
  final double l = color.l;
  final double croma = math.sqrt(color.a * color.a + color.b * color.b);
  // Matiz en grados, de 0 a 360. En Lab el rojo puro esta cerca de 40 y el azul
  // puro cerca de 306.
  final double matiz =
      (math.atan2(color.b, color.a) * 180 / math.pi + 360) % 360;

  // Sin color: solo cuenta la luminosidad.
  if (croma < 10) {
    if (l >= 85) return CategoriaColor.blanco;
    if (l <= 25) return CategoriaColor.negro;
    return CategoriaColor.gris;
  }
  // Muy oscuro y casi sin color: el negro con un matiz de la tela.
  if (l <= 20 && croma < 15) return CategoriaColor.negro;

  // Calidos apagados: el beige es claro y poco saturado, el marron es oscuro.
  if (matiz >= 40 && matiz < 110 && croma < 35 && l >= 65) {
    return CategoriaColor.beige;
  }
  if (matiz >= 30 && matiz < 90 && l < 50 && croma < 60) {
    return CategoriaColor.marron;
  }

  if (matiz >= 340 || matiz < 25) {
    return l >= 60 ? CategoriaColor.rosa : CategoriaColor.rojo;
  }
  if (matiz < 50) return CategoriaColor.rojo;
  if (matiz < 75) return CategoriaColor.naranja;
  if (matiz < 115) {
    // El amarillo oscuro y verdoso es un verde oliva.
    return matiz >= 90 && l < 60
        ? CategoriaColor.verde
        : CategoriaColor.amarillo;
  }
  if (matiz < 185) return CategoriaColor.verde;
  if (matiz < 310) return CategoriaColor.azul;
  return CategoriaColor.morado;
}
