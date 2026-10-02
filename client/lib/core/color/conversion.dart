/// Conversiones de color del nivel 0.
///
/// La cadena es: valor codificado, curva del perfil, RGB lineal, XYZ (D50 del
/// perfil), adaptacion cromatica Bradford a D65, y de ahi a Lab con blanco D65
/// o a sRGB. Cualquier correccion de balance debe hacerse sobre el RGB lineal,
/// nunca sobre valores con gamma.
///
/// Los valores salen sin recortar al gamut: un color fuera de sRGB conserva su
/// Lab real. Solo [perfilASrgb8] recorta, porque ahi hay que escribir un byte.
library;

import 'dart:math' as math;

import 'package:wearhack/core/color/perfil_icc.dart';
import 'package:wearhack/core/vocabulario.dart';

/// Adaptacion cromatica Bradford de D50 (espacio de conexion ICC) a D65.
const List<List<double>> matrizBradfordD50aD65 = <List<double>>[
  <double>[0.9555766, -0.0230393, 0.0631636],
  <double>[-0.0282895, 1.0099416, 0.0210077],
  <double>[0.0122982, -0.0204830, 1.3299098],
];

/// XYZ D65 a sRGB lineal.
const List<List<double>> _xyzD65ASrgbLineal = <List<double>>[
  <double>[3.2404542, -1.5371385, -0.4985314],
  <double>[-0.9692660, 1.8760108, 0.0415560],
  <double>[0.0556434, -0.2040259, 1.0572252],
];

/// Blanco de referencia D65.
const Xyz blancoD65 = (0.95047, 1.0, 1.08883);

Xyz _multiplicar(List<List<double>> m, Xyz v) => (
  m[0][0] * v.$1 + m[0][1] * v.$2 + m[0][2] * v.$3,
  m[1][0] * v.$1 + m[1][1] * v.$2 + m[1][2] * v.$3,
  m[2][0] * v.$1 + m[2][1] * v.$2 + m[2][2] * v.$3,
);

/// Pasa un XYZ referido a D50 (el del perfil) a XYZ referido a D65.
Xyz xyzD50aD65(Xyz d50) => _multiplicar(matrizBradfordD50aD65, d50);

/// Pasa un XYZ referido a D65 a Lab con blanco D65.
ColorLab xyzD65aLab(Xyz xyz) {
  double f(double t) {
    const double epsilon = 216 / 24389;
    const double kappa = 24389 / 27;
    return t > epsilon ? math.pow(t, 1 / 3).toDouble() : (kappa * t + 16) / 116;
  }

  final double fx = f(xyz.$1 / blancoD65.$1);
  final double fy = f(xyz.$2 / blancoD65.$2);
  final double fz = f(xyz.$3 / blancoD65.$3);
  return ColorLab(l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz));
}

/// Lab con blanco D65 de un color de 8 bits interpretado con [perfil].
///
/// Es la medicion que importa para la colorimetria: el mismo byte da un Lab
/// distinto segun el perfil, y asumir sRGB cuando era Display P3 desplaza a*
/// y b*.
ColorLab perfilALab(PerfilRgb perfil, int r, int g, int b) =>
    xyzD65aLab(xyzD50aD65(perfil.aXyzD50(r / 255.0, g / 255.0, b / 255.0)));

/// sRGB lineal (sin recortar) de un color de 8 bits interpretado con [perfil].
Xyz perfilASrgbLineal(PerfilRgb perfil, int r, int g, int b) {
  final Xyz d65 = xyzD50aD65(perfil.aXyzD50(r / 255.0, g / 255.0, b / 255.0));
  return _multiplicar(_xyzD65ASrgbLineal, d65);
}

/// Convierte un color de 8 bits de [perfil] a sRGB de 8 bits.
///
/// Recorta al gamut de sRGB: un color de Display P3 mas saturado de lo que
/// sRGB puede mostrar queda en el borde.
({int r, int g, int b}) perfilASrgb8(PerfilRgb perfil, int r, int g, int b) {
  final Xyz lineal = perfilASrgbLineal(perfil, r, g, b);
  return (
    r: _codificarSrgb(lineal.$1),
    g: _codificarSrgb(lineal.$2),
    b: _codificarSrgb(lineal.$3),
  );
}

int _codificarSrgb(double lineal) {
  final double v = lineal.clamp(0.0, 1.0).toDouble();
  final double codificado = v <= 0.0031308
      ? 12.92 * v
      : 1.055 * math.pow(v, 1 / 2.4).toDouble() - 0.055;
  return (codificado * 255).round().clamp(0, 255);
}
