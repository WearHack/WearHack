/// Lector minimo de perfiles de color ICC de tipo "matriz y curvas".
///
/// Existe por una razon concreta, medida: la libreria `image` decodifica el
/// perfil de un JPEG con 2 bytes de mas (los de secuencia y conteo del segmento
/// APP2), y un PNG escrito con ella lleva ese perfil roto. El motor de Flutter
/// (`dart:ui`) lo descarta sin avisar. Como el nivel 0 de la colorimetria exige
/// saber en que espacio estan los colores, el cliente lee el perfil el mismo.
///
/// Soporta lo que usan las camaras de telefono: sRGB, Display P3 y similares,
/// que son tres colorantes XYZ mas una curva por canal (`curv` o `para`). Un
/// perfil basado en tablas de busqueda (LUT) no se soporta, y falla en voz alta
/// con [PerfilIccNoSoportado] en lugar de adivinar.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Una terna XYZ.
typedef Xyz = (double, double, double);

/// El perfil no es de un tipo que este lector sepa interpretar.
class PerfilIccNoSoportado implements Exception {
  const PerfilIccNoSoportado(this.motivo);

  final String motivo;

  @override
  String toString() => 'PerfilIccNoSoportado: $motivo';
}

/// Curva de un canal: pasa de valor codificado (0 a 1) a luz lineal (0 a 1).
class CurvaTonal {
  const CurvaTonal._(this._funcion);

  final double Function(double) _funcion;

  /// Convierte un valor codificado en luz lineal. El argumento se recorta a
  /// [0, 1] antes de evaluar.
  double aLineal(double codificado) =>
      _funcion(codificado.clamp(0.0, 1.0).toDouble());

  /// La curva de transferencia de sRGB. Display P3 usa la misma.
  static const CurvaTonal srgb = CurvaTonal._(_srgbALineal);

  static double _srgbALineal(double v) =>
      v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

  /// Curva con el exponente `gamma` de un tag `curv` de un solo valor.
  static CurvaTonal _gamma(double gamma) =>
      CurvaTonal._((v) => math.pow(v, gamma).toDouble());

  /// Curva de un tag `curv` con tabla, interpolada de forma lineal.
  static CurvaTonal _tabla(List<double> tabla) => CurvaTonal._((v) {
    final double pos = v * (tabla.length - 1);
    final int i = pos.floor();
    if (i >= tabla.length - 1) return tabla.last;
    final double t = pos - i;
    return tabla[i] * (1 - t) + tabla[i + 1] * t;
  });

  /// Curva parametrica de un tag `para`, segun las funciones 0 a 4 del
  /// estandar ICC.
  static CurvaTonal _parametrica(int tipo, List<double> p) {
    final double g = p[0];
    return switch (tipo) {
      0 => CurvaTonal._((x) => math.pow(x, g).toDouble()),
      1 => CurvaTonal._((x) {
        final double a = p[1], b = p[2];
        return x >= -b / a ? math.pow(a * x + b, g).toDouble() : 0.0;
      }),
      2 => CurvaTonal._((x) {
        final double a = p[1], b = p[2], c = p[3];
        return x >= -b / a ? math.pow(a * x + b, g).toDouble() + c : c;
      }),
      3 => CurvaTonal._((x) {
        final double a = p[1], b = p[2], c = p[3], d = p[4];
        return x >= d ? math.pow(a * x + b, g).toDouble() : c * x;
      }),
      4 => CurvaTonal._((x) {
        final double a = p[1], b = p[2], c = p[3], d = p[4], e = p[5], f = p[6];
        return x >= d ? math.pow(a * x + b, g).toDouble() + e : c * x + f;
      }),
      _ => throw PerfilIccNoSoportado('curva parametrica de tipo $tipo'),
    };
  }
}

/// Un espacio RGB descrito por sus colorantes y sus curvas.
///
/// Los colorantes estan en XYZ referido a D50, que es el espacio de conexion
/// del estandar ICC.
class PerfilRgb {
  const PerfilRgb({
    required this.rojo,
    required this.verde,
    required this.azul,
    required this.curvaRojo,
    required this.curvaVerde,
    required this.curvaAzul,
  });

  final Xyz rojo;
  final Xyz verde;
  final Xyz azul;
  final CurvaTonal curvaRojo;
  final CurvaTonal curvaVerde;
  final CurvaTonal curvaAzul;

  /// sRGB, con los colorantes de su perfil ICC oficial (adaptados a D50).
  ///
  /// Es lo que se asume cuando una imagen no trae perfil. Asumirlo es una
  /// apuesta: si la foto era en realidad Display P3, a* y b* salen desplazados.
  static const PerfilRgb srgb = PerfilRgb(
    rojo: (0.4360747, 0.2225045, 0.0139322),
    verde: (0.3850649, 0.7168786, 0.0971045),
    azul: (0.1430804, 0.0606169, 0.7141733),
    curvaRojo: CurvaTonal.srgb,
    curvaVerde: CurvaTonal.srgb,
    curvaAzul: CurvaTonal.srgb,
  );

  /// Convierte un color codificado (cada canal de 0 a 1) en XYZ referido a D50.
  Xyz aXyzD50(double r, double g, double b) {
    final double lr = curvaRojo.aLineal(r);
    final double lg = curvaVerde.aLineal(g);
    final double lb = curvaAzul.aLineal(b);
    return (
      lr * rojo.$1 + lg * verde.$1 + lb * azul.$1,
      lr * rojo.$2 + lg * verde.$2 + lb * azul.$2,
      lr * rojo.$3 + lg * verde.$3 + lb * azul.$3,
    );
  }

  /// Lee un perfil ICC completo.
  ///
  /// Lanza [PerfilIccNoSoportado] si no es un perfil RGB de matriz y curvas, y
  /// [FormatException] si los bytes no son un perfil ICC valido.
  factory PerfilRgb.desdeBytes(Uint8List bytes) {
    if (bytes.length < 132) {
      throw const FormatException('Perfil ICC demasiado corto');
    }
    final ByteData datos = ByteData.sublistView(bytes);
    if (_firma(datos, 36) != 'acsp') {
      throw const FormatException('El perfil ICC no lleva la firma "acsp"');
    }
    final String espacio = _firma(datos, 16);
    if (espacio != 'RGB ') {
      throw PerfilIccNoSoportado('el espacio del perfil es "$espacio"');
    }

    final int numeroDeTags = datos.getUint32(128);
    final Map<String, (int, int)> tags = <String, (int, int)>{};
    for (int i = 0; i < numeroDeTags; i++) {
      final int base = 132 + i * 12;
      if (base + 12 > bytes.length) {
        throw const FormatException('La tabla de tags se sale del perfil');
      }
      final int inicio = datos.getUint32(base + 4);
      final int largo = datos.getUint32(base + 8);
      if (inicio + largo > bytes.length) {
        throw FormatException('El tag "${_firma(datos, base)}" se sale');
      }
      tags[_firma(datos, base)] = (inicio, largo);
    }

    Xyz colorante(String nombre) {
      final (int, int)? t = tags[nombre];
      if (t == null) {
        throw PerfilIccNoSoportado('falta el tag $nombre (perfil de LUT?)');
      }
      if (_firma(datos, t.$1) != 'XYZ ') {
        throw FormatException('El tag $nombre no es de tipo XYZ');
      }
      return (
        _s15Fixed16(datos, t.$1 + 8),
        _s15Fixed16(datos, t.$1 + 12),
        _s15Fixed16(datos, t.$1 + 16),
      );
    }

    CurvaTonal curva(String nombre) {
      final (int, int)? t = tags[nombre];
      if (t == null) {
        throw PerfilIccNoSoportado('falta el tag $nombre (perfil de LUT?)');
      }
      return _leerCurva(datos, t.$1, nombre);
    }

    return PerfilRgb(
      rojo: colorante('rXYZ'),
      verde: colorante('gXYZ'),
      azul: colorante('bXYZ'),
      curvaRojo: curva('rTRC'),
      curvaVerde: curva('gTRC'),
      curvaAzul: curva('bTRC'),
    );
  }

  static CurvaTonal _leerCurva(ByteData datos, int inicio, String nombre) {
    final String tipo = _firma(datos, inicio);
    if (tipo == 'curv') {
      final int n = datos.getUint32(inicio + 8);
      if (n == 0) return CurvaTonal._((v) => v);
      if (n == 1) {
        return CurvaTonal._gamma(datos.getUint16(inicio + 12) / 256.0);
      }
      return CurvaTonal._tabla(<double>[
        for (int i = 0; i < n; i++)
          datos.getUint16(inicio + 12 + i * 2) / 65535.0,
      ]);
    }
    if (tipo == 'para') {
      final int funcion = datos.getUint16(inicio + 8);
      const List<int> numeroDeParametros = <int>[1, 3, 4, 5, 7];
      if (funcion >= numeroDeParametros.length) {
        throw PerfilIccNoSoportado('curva parametrica de tipo $funcion');
      }
      return CurvaTonal._parametrica(funcion, <double>[
        for (int i = 0; i < numeroDeParametros[funcion]; i++)
          _s15Fixed16(datos, inicio + 12 + i * 4),
      ]);
    }
    throw PerfilIccNoSoportado('el tag $nombre es de tipo "$tipo"');
  }

  static String _firma(ByteData datos, int posicion) => String.fromCharCodes(
    Uint8List.sublistView(datos, posicion, posicion + 4),
  );

  static double _s15Fixed16(ByteData datos, int posicion) =>
      datos.getInt32(posicion) / 65536.0;
}
