/// Fabrica perfiles ICC y JPEG en memoria, para que ningun test dependa de un
/// archivo de perfil ni de una foto.
library;

import 'dart:typed_data';

import 'package:wearhack/core/color/conversion.dart';
import 'package:wearhack/core/color/perfil_icc.dart';

/// Colorantes de Display P3 con blanco D65 (la matriz estandar P3-D65 a XYZ).
const Xyz p3RojoD65 = (0.4865709, 0.2289746, 0.0);
const Xyz p3VerdeD65 = (0.2656677, 0.6917385, 0.0451134);
const Xyz p3AzulD65 = (0.1982173, 0.0792869, 1.0439444);

/// Invierte una matriz 3x3.
List<List<double>> invertir3x3(List<List<double>> m) {
  final double a = m[0][0], b = m[0][1], c = m[0][2];
  final double d = m[1][0], e = m[1][1], f = m[1][2];
  final double g = m[2][0], h = m[2][1], i = m[2][2];
  final double det =
      a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
  return <List<double>>[
    <double>[
      (e * i - f * h) / det,
      (c * h - b * i) / det,
      (b * f - c * e) / det,
    ],
    <double>[
      (f * g - d * i) / det,
      (a * i - c * g) / det,
      (c * d - a * f) / det,
    ],
    <double>[
      (d * h - e * g) / det,
      (b * g - a * h) / det,
      (a * e - b * d) / det,
    ],
  ];
}

/// Lleva un XYZ de D65 a D50, que es como los guarda un perfil ICC.
Xyz xyzD65aD50(Xyz d65) {
  final List<List<double>> m = invertir3x3(matrizBradfordD50aD65);
  return (
    m[0][0] * d65.$1 + m[0][1] * d65.$2 + m[0][2] * d65.$3,
    m[1][0] * d65.$1 + m[1][1] * d65.$2 + m[1][2] * d65.$3,
    m[2][0] * d65.$1 + m[2][1] * d65.$2 + m[2][2] * d65.$3,
  );
}

Uint8List _s15f16(double v) {
  final ByteData d = ByteData(4)..setInt32(0, (v * 65536).round());
  return d.buffer.asUint8List();
}

Uint8List _u32(int v) => (ByteData(4)..setUint32(0, v)).buffer.asUint8List();

Uint8List _rellenar(Uint8List bytes) {
  final int resto = bytes.length % 4;
  if (resto == 0) return bytes;
  return Uint8List.fromList(<int>[...bytes, ...List<int>.filled(4 - resto, 0)]);
}

Uint8List _firma(String s) => Uint8List.fromList(s.codeUnits);

Uint8List tagXyz(Xyz v) => Uint8List.fromList(<int>[
  ..._firma('XYZ '),
  ..._u32(0),
  ..._s15f16(v.$1),
  ..._s15f16(v.$2),
  ..._s15f16(v.$3),
]);

/// Curva `curv` de un solo exponente (gamma).
Uint8List curvaGamma(double gamma) {
  final ByteData cuerpo = ByteData(2)..setUint16(0, (gamma * 256).round());
  return _rellenar(
    Uint8List.fromList(<int>[
      ..._firma('curv'),
      ..._u32(0),
      ..._u32(1),
      ...cuerpo.buffer.asUint8List(),
    ]),
  );
}

/// Curva `curv` con tabla de 16 bits.
Uint8List curvaTabla(List<int> valores) {
  final ByteData cuerpo = ByteData(valores.length * 2);
  for (int i = 0; i < valores.length; i++) {
    cuerpo.setUint16(i * 2, valores[i]);
  }
  return _rellenar(
    Uint8List.fromList(<int>[
      ..._firma('curv'),
      ..._u32(0),
      ..._u32(valores.length),
      ...cuerpo.buffer.asUint8List(),
    ]),
  );
}

/// Curva `para` de la funcion `tipo` con sus parametros.
Uint8List curvaParametrica(int tipo, List<double> parametros) {
  final ByteData cabecera = ByteData(4)..setUint16(0, tipo);
  return Uint8List.fromList(<int>[
    ..._firma('para'),
    ..._u32(0),
    ...cabecera.buffer.asUint8List(),
    for (final double p in parametros) ..._s15f16(p),
  ]);
}

/// La curva sRGB como `para` de tipo 3.
Uint8List curvaSrgbParametrica() => curvaParametrica(3, <double>[
  2.4,
  1 / 1.055,
  0.055 / 1.055,
  1 / 12.92,
  0.04045,
]);

/// Un perfil ICC de matriz y curvas, completo y con tamano coherente.
///
/// Los parametros `espacio`, `incluirMatriz` y `firma` permiten fabricar
/// perfiles invalidos o no soportados a proposito.
Uint8List construirPerfil({
  required Xyz rojo,
  required Xyz verde,
  required Xyz azul,
  required Uint8List curva,
  String espacio = 'RGB ',
  bool incluirMatriz = true,
  String firma = 'acsp',
  int relleno = 0,
}) {
  final List<(String, Uint8List)> tags = <(String, Uint8List)>[
    if (incluirMatriz) ('rXYZ', tagXyz(rojo)),
    if (incluirMatriz) ('gXYZ', tagXyz(verde)),
    if (incluirMatriz) ('bXYZ', tagXyz(azul)),
    ('rTRC', curva),
    ('gTRC', curva),
    ('bTRC', curva),
    if (relleno > 0) ('priv', _rellenar(Uint8List(relleno))),
  ];
  final int inicioDatos = 128 + 4 + tags.length * 12;
  final BytesBuilder tabla = BytesBuilder();
  final BytesBuilder datos = BytesBuilder();
  // Las tres curvas apuntan al mismo bloque, como hacen los perfiles reales.
  int? posicionCurva;
  for (final (String nombre, Uint8List contenido) in tags) {
    final bool esCurva = nombre.endsWith('TRC');
    final int posicion;
    if (esCurva && posicionCurva != null) {
      posicion = posicionCurva;
    } else {
      posicion = inicioDatos + datos.length;
      datos.add(contenido);
      if (esCurva) posicionCurva = posicion;
    }
    tabla
      ..add(_firma(nombre))
      ..add(_u32(posicion))
      ..add(_u32(contenido.length));
  }
  final int total = inicioDatos + datos.length;
  final Uint8List cabecera = Uint8List(128);
  final ByteData vista = ByteData.sublistView(cabecera)
    ..setUint32(0, total)
    ..setUint32(8, 0x02400000);
  cabecera.setRange(12, 16, _firma('mntr'));
  cabecera.setRange(16, 20, _firma(espacio));
  cabecera.setRange(20, 24, _firma('XYZ '));
  cabecera.setRange(36, 40, _firma(firma));
  assert(vista.lengthInBytes == 128);
  return Uint8List.fromList(<int>[
    ...cabecera,
    ..._u32(tags.length),
    ...tabla.toBytes(),
    ...datos.toBytes(),
  ]);
}

/// Display P3: colorantes P3-D65 adaptados a D50, con la curva de sRGB.
Uint8List perfilDisplayP3() => construirPerfil(
  rojo: xyzD65aD50(p3RojoD65),
  verde: xyzD65aD50(p3VerdeD65),
  azul: xyzD65aD50(p3AzulD65),
  curva: curvaSrgbParametrica(),
);

/// sRGB, con los colorantes D50 del perfil oficial y la curva como `para`.
Uint8List perfilSrgb() => construirPerfil(
  rojo: PerfilRgb.srgb.rojo,
  verde: PerfilRgb.srgb.verde,
  azul: PerfilRgb.srgb.azul,
  curva: curvaSrgbParametrica(),
);

/// Inserta un perfil en un JPEG como lo haria una camara: uno o varios
/// segmentos APP2 con secuencia y conteo, en el orden indicado.
Uint8List jpegConIcc(
  Uint8List jpegSinPerfil,
  Uint8List perfil, {
  int maximoPorSegmento = 65519,
  List<int>? ordenDeEscritura,
}) {
  final int n = (perfil.length / maximoPorSegmento).ceil();
  final List<Uint8List> segmentos = <Uint8List>[];
  for (int s = 0; s < n; s++) {
    final Uint8List trozo = Uint8List.sublistView(
      perfil,
      s * maximoPorSegmento,
      (s + 1) * maximoPorSegmento > perfil.length
          ? perfil.length
          : (s + 1) * maximoPorSegmento,
    );
    final int largo = 2 + 12 + 2 + trozo.length;
    segmentos.add(
      Uint8List.fromList(<int>[
        0xFF,
        0xE2,
        largo >> 8,
        largo & 0xFF,
        ...'ICC_PROFILE'.codeUnits,
        0,
        s + 1,
        n,
        ...trozo,
      ]),
    );
  }
  final List<int> orden = ordenDeEscritura ?? List<int>.generate(n, (s) => s);
  return Uint8List.fromList(<int>[
    ...jpegSinPerfil.sublist(0, 2),
    for (final int s in orden) ...segmentos[s],
    ...jpegSinPerfil.sublist(2),
  ]);
}
