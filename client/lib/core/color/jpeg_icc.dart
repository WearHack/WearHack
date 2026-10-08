/// Extrae el perfil ICC de un JPEG sin recodificarlo.
///
/// Un perfil de color viaja en uno o varios segmentos APP2 con la firma
/// `ICC_PROFILE\0`, un numero de secuencia y un conteo. Esto los ensambla en
/// orden. Es el camino fiable porque no pasa por ninguna libreria de imagen:
/// la foto original no se toca, asi que su perfil queda intacto.
library;

import 'dart:typed_data';

const List<int> _firmaIcc = <int>[
  0x49, 0x43, 0x43, 0x5F, 0x50, 0x52, 0x4F, 0x46, 0x49, 0x4C, 0x45, 0x00, //
];

/// Devuelve los bytes del perfil ICC del JPEG, o `null` si no trae ninguno.
///
/// Lanza [FormatException] si el archivo no es un JPEG, si un segmento se sale
/// del archivo, o si los fragmentos del perfil son inconsistentes.
Uint8List? extraerIccDeJpeg(Uint8List jpeg) {
  if (jpeg.length < 4 || jpeg[0] != 0xFF || jpeg[1] != 0xD8) {
    throw const FormatException('No es un JPEG (falta SOI)');
  }

  final Map<int, Uint8List> fragmentos = <int, Uint8List>{};
  int? conteo;
  int i = 2;
  while (i + 4 <= jpeg.length) {
    if (jpeg[i] != 0xFF) {
      throw FormatException('Marcador JPEG esperado en el byte $i');
    }
    final int marcador = jpeg[i + 1];
    if (marcador == 0xFF) {
      i++; // relleno
      continue;
    }
    // Sin largo: SOI, TEM, RSTn. Fin de los metadatos: SOS y EOI.
    if (marcador == 0xD8 ||
        marcador == 0x01 ||
        (marcador >= 0xD0 && marcador <= 0xD7)) {
      i += 2;
      continue;
    }
    if (marcador == 0xDA || marcador == 0xD9) break;

    final int largo = (jpeg[i + 2] << 8) | jpeg[i + 3];
    if (largo < 2 || i + 2 + largo > jpeg.length) {
      throw FormatException('Segmento JPEG fuera de rango en el byte $i');
    }
    if (marcador == 0xE2 && largo >= 2 + _firmaIcc.length + 2) {
      final int datos = i + 4;
      if (_coincideFirma(jpeg, datos)) {
        final int secuencia = jpeg[datos + _firmaIcc.length];
        final int total = jpeg[datos + _firmaIcc.length + 1];
        if (secuencia == 0 || total == 0 || secuencia > total) {
          throw const FormatException('Secuencia ICC invalida');
        }
        if (conteo != null && conteo != total) {
          throw const FormatException('Conteo ICC inconsistente');
        }
        conteo = total;
        if (fragmentos.containsKey(secuencia)) {
          throw const FormatException('Fragmento ICC repetido');
        }
        fragmentos[secuencia] = Uint8List.sublistView(
          jpeg,
          datos + _firmaIcc.length + 2,
          i + 2 + largo,
        );
      }
    }
    i += 2 + largo;
  }

  if (fragmentos.isEmpty) return null;
  if (fragmentos.length != conteo) {
    throw const FormatException('Faltan fragmentos del perfil ICC');
  }
  final BytesBuilder perfil = BytesBuilder(copy: false);
  for (int s = 1; s <= conteo!; s++) {
    final Uint8List? fragmento = fragmentos[s];
    if (fragmento == null) {
      throw const FormatException('Faltan fragmentos del perfil ICC');
    }
    perfil.add(fragmento);
  }
  return perfil.toBytes();
}

bool _coincideFirma(Uint8List bytes, int desde) {
  for (int k = 0; k < _firmaIcc.length; k++) {
    if (bytes[desde + k] != _firmaIcc[k]) return false;
  }
  return true;
}
