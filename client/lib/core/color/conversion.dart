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
import 'dart:typed_data';

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

/// sRGB de 8 bits de un Lab con blanco D65: la inversa de [xyzD65aLab].
///
/// Sirve para pintar en pantalla un color que se midio en Lab. Un Lab fuera del
/// gamut de sRGB se recorta al borde, igual que en [perfilASrgb8].
({int r, int g, int b}) labASrgb8(ColorLab lab) {
  const double epsilon = 216 / 24389;
  const double kappa = 24389 / 27;
  final double fy = (lab.l + 16) / 116;
  final double fx = fy + lab.a / 500;
  final double fz = fy - lab.b / 200;
  final double fx3 = fx * fx * fx;
  final double fz3 = fz * fz * fz;
  final double xr = fx3 > epsilon ? fx3 : (116 * fx - 16) / kappa;
  final double yr = lab.l > kappa * epsilon ? fy * fy * fy : lab.l / kappa;
  final double zr = fz3 > epsilon ? fz3 : (116 * fz - 16) / kappa;
  final Xyz lineal = _multiplicar(_xyzD65ASrgbLineal, (
    xr * blancoD65.$1,
    yr * blancoD65.$2,
    zr * blancoD65.$3,
  ));
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

/// Convierte a sRGB muchos pixeles de 8 bits de un mismo perfil.
///
/// Un recorte tiene millones de pixeles, y [perfilASrgb8] llama a `pow` varias
/// veces por cada uno. Aqui la curva del perfil se tabula (256 entradas por
/// canal), los tres pasos matriciales (colorantes, Bradford, XYZ a sRGB) se
/// funden en una sola matriz, y la curva de sRGB se tabula tambien. El
/// resultado difiere de [perfilASrgb8] en un byte como mucho.
class ConversorASrgb {
  ConversorASrgb(PerfilRgb perfil)
    : _rojo = _tabular(perfil.curvaRojo),
      _verde = _tabular(perfil.curvaVerde),
      _azul = _tabular(perfil.curvaAzul),
      _m = _matrizCombinada(perfil);

  static const int _pasosDeCodificacion = 16384;

  static final Uint8List _codificar = Uint8List.fromList(<int>[
    for (int i = 0; i < _pasosDeCodificacion; i++)
      _codificarSrgb(i / (_pasosDeCodificacion - 1)),
  ]);

  final Float64List _rojo;
  final Float64List _verde;
  final Float64List _azul;
  final Float64List _m;

  static Float64List _tabular(CurvaTonal curva) => Float64List.fromList(
    <double>[for (int i = 0; i < 256; i++) curva.aLineal(i / 255.0)],
  );

  static Float64List _matrizCombinada(PerfilRgb p) {
    final List<List<double>> colorantes = <List<double>>[
      <double>[p.rojo.$1, p.verde.$1, p.azul.$1],
      <double>[p.rojo.$2, p.verde.$2, p.azul.$2],
      <double>[p.rojo.$3, p.verde.$3, p.azul.$3],
    ];
    final List<List<double>> m = _producto(
      _xyzD65ASrgbLineal,
      _producto(matrizBradfordD50aD65, colorantes),
    );
    return Float64List.fromList(<double>[for (final List<double> f in m) ...f]);
  }

  static List<List<double>> _producto(
    List<List<double>> a,
    List<List<double>> b,
  ) => <List<double>>[
    for (int i = 0; i < 3; i++)
      <double>[
        for (int j = 0; j < 3; j++)
          a[i][0] * b[0][j] + a[i][1] * b[1][j] + a[i][2] * b[2][j],
      ],
  ];

  /// Convierte en sitio un buffer de pixeles RGB empaquetados (3 bytes por
  /// pixel, sin canal alfa).
  void convertirEnSitio(Uint8List rgb) {
    if (rgb.length % 3 != 0) {
      throw ArgumentError(
        'El buffer no es RGB empaquetado (3 bytes por pixel)',
      );
    }
    const double tope = _pasosDeCodificacion - 1;
    for (int i = 0; i < rgb.length; i += 3) {
      final double r = _rojo[rgb[i]];
      final double g = _verde[rgb[i + 1]];
      final double b = _azul[rgb[i + 2]];
      rgb[i] = _codificar[_indice(_m[0] * r + _m[1] * g + _m[2] * b, tope)];
      rgb[i + 1] = _codificar[_indice(_m[3] * r + _m[4] * g + _m[5] * b, tope)];
      rgb[i + 2] = _codificar[_indice(_m[6] * r + _m[7] * g + _m[8] * b, tope)];
    }
  }

  static int _indice(double lineal, double tope) {
    if (lineal <= 0) return 0;
    if (lineal >= 1) return tope.toInt();
    return (lineal * tope + 0.5).floor();
  }
}
