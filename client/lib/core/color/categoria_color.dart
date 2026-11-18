/// De un color en Lab a la categoria de color de la prenda (#58).
///
/// El color se asigna al bloque mas cercano de los 267 de ISCC-NBS, medido con
/// CIEDE2000 (ΔE00), y el bloque trae su categoria. La tabla esta en
/// `assets/color/iscc_nbs.json`: centroides de Kelly (1958, NBS/NIST) pasados a
/// Lab D65, y la traduccion bloque -> categoria. La genera
/// `tools/iscc-nbs/generar_tabla.py`; para cambiar una categoria se cambia alli
/// y se regenera, no aqui.
///
/// Los centroides no se mueven: son el estandar. Lo que se ajusta con las
/// correcciones de los usuarios es la traduccion (tarea del Core).
///
/// **No devuelve `multicolor`.** Eso no es una propiedad de un color sino de la
/// prenda (un patron con varios colores), y lo decide quien ve el patron.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:wearhack/core/vocabulario.dart';

/// Ruta del asset con la tabla.
const String assetTablaIsccNbs = 'assets/color/iscc_nbs.json';

/// Un bloque ISCC-NBS: su centroide en Lab D65 y su categoria.
class BloqueIsccNbs {
  const BloqueIsccNbs({
    required this.numero,
    required this.nombre,
    required this.lab,
    required this.categoria,
  });

  /// Numero del bloque en la NBS Circular 553 (1 a 267).
  final int numero;

  /// Nombre ISCC-NBS en ingles, p. ej. `dark grayish blue`.
  final String nombre;
  final ColorLab lab;
  final CategoriaColor categoria;
}

/// La tabla de 267 bloques.
class TablaIsccNbs {
  TablaIsccNbs(List<BloqueIsccNbs> bloques)
    : bloques = List<BloqueIsccNbs>.unmodifiable(bloques) {
    if (bloques.isEmpty) {
      throw const FormatException('La tabla ISCC-NBS no tiene bloques');
    }
  }

  /// Lee el JSON de `assets/color/iscc_nbs.json`.
  factory TablaIsccNbs.desdeJson(String texto) {
    final Map<String, Object?> json = jsonDecode(texto) as Map<String, Object?>;
    final List<Object?> bloques = json['bloques']! as List<Object?>;
    return TablaIsccNbs(<BloqueIsccNbs>[
      for (final Object? b in bloques) _bloque(b! as Map<String, Object?>),
    ]);
  }

  final List<BloqueIsccNbs> bloques;

  /// El bloque con menor ΔE00 al color.
  BloqueIsccNbs bloqueMasCercano(ColorLab color) {
    BloqueIsccNbs mejor = bloques.first;
    double distancia = double.infinity;
    for (final BloqueIsccNbs b in bloques) {
      final double d = deltaE00(color, b.lab);
      if (d < distancia) {
        distancia = d;
        mejor = b;
      }
    }
    return mejor;
  }

  /// La categoria de un color: la de su bloque mas cercano.
  CategoriaColor categoria(ColorLab color) => bloqueMasCercano(color).categoria;
}

BloqueIsccNbs _bloque(Map<String, Object?> b) {
  final List<Object?> lab = b['lab']! as List<Object?>;
  return BloqueIsccNbs(
    numero: (b['numero']! as num).toInt(),
    nombre: b['nombre']! as String,
    lab: ColorLab(
      l: (lab[0]! as num).toDouble(),
      a: (lab[1]! as num).toDouble(),
      b: (lab[2]! as num).toDouble(),
    ),
    categoria: CategoriaColor.desdeCodigo(b['categoria']! as String),
  );
}

/// Diferencia de color CIEDE2000 (Sharma, Wu y Dalal, 2005), con kL = kC = kH
/// = 1.
double deltaE00(ColorLab x, ColorLab y) {
  const double grado = math.pi / 180;
  final double c1 = math.sqrt(x.a * x.a + x.b * x.b);
  final double c2 = math.sqrt(y.a * y.a + y.b * y.b);
  final double cMedio7 = math.pow((c1 + c2) / 2, 7).toDouble();
  final double g =
      0.5 * (1 - math.sqrt(cMedio7 / (cMedio7 + math.pow(25, 7).toDouble())));
  final double a1 = (1 + g) * x.a;
  final double a2 = (1 + g) * y.a;
  final double cp1 = math.sqrt(a1 * a1 + x.b * x.b);
  final double cp2 = math.sqrt(a2 * a2 + y.b * y.b);
  double matiz(double b, double a) {
    if (a == 0 && b == 0) return 0;
    final double h = math.atan2(b, a) / grado;
    return h < 0 ? h + 360 : h;
  }

  final double h1 = matiz(x.b, a1);
  final double h2 = matiz(y.b, a2);

  final double dL = y.l - x.l;
  final double dC = cp2 - cp1;
  double dh = 0;
  if (cp1 * cp2 != 0) {
    dh = h2 - h1;
    if (dh > 180) {
      dh -= 360;
    } else if (dh < -180) {
      dh += 360;
    }
  }
  final double dH = 2 * math.sqrt(cp1 * cp2) * math.sin(dh * grado / 2);

  final double lMedio = (x.l + y.l) / 2;
  final double cpMedio = (cp1 + cp2) / 2;
  double hMedio = h1 + h2;
  if (cp1 * cp2 != 0) {
    if ((h1 - h2).abs() <= 180) {
      hMedio = (h1 + h2) / 2;
    } else if (h1 + h2 < 360) {
      hMedio = (h1 + h2 + 360) / 2;
    } else {
      hMedio = (h1 + h2 - 360) / 2;
    }
  }
  final double t =
      1 -
      0.17 * math.cos((hMedio - 30) * grado) +
      0.24 * math.cos(2 * hMedio * grado) +
      0.32 * math.cos((3 * hMedio + 6) * grado) -
      0.20 * math.cos((4 * hMedio - 63) * grado);
  final double dTheta = 30 * math.exp(-math.pow((hMedio - 275) / 25, 2));
  final double cpMedio7 = math.pow(cpMedio, 7).toDouble();
  final double rC =
      2 * math.sqrt(cpMedio7 / (cpMedio7 + math.pow(25, 7).toDouble()));
  final double lm50 = (lMedio - 50) * (lMedio - 50);
  final double sL = 1 + 0.015 * lm50 / math.sqrt(20 + lm50);
  final double sC = 1 + 0.045 * cpMedio;
  final double sH = 1 + 0.015 * cpMedio * t;
  final double rT = -math.sin(2 * dTheta * grado) * rC;

  final double l = dL / sL;
  final double c = dC / sC;
  final double h = dH / sH;
  return math.sqrt(l * l + c * c + h * h + rT * c * h);
}
