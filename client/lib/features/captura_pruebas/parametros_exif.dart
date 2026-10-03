/// Parametros de camara leidos del EXIF de la foto.
///
/// El plugin `camera` no expone ISO, tiempo de exposicion ni balance de blancos
/// en la foto (verificado en su codigo: esos datos solo existen en los
/// fotogramas del stream, y en Android ni siquiera ahi). El EXIF del JPEG que
/// guarda la camara es la unica fuente. Lo que no venga queda en `null`: no se
/// inventa.
///
/// Que significa cada campo, porque la spec solo dice "exposicion", "iso" y
/// "balance_blancos":
///
/// - `exposicion`: el **tiempo de exposicion en segundos** (EXIF ExposureTime),
///   por ejemplo 0.0166 para 1/60 s. No es la compensacion de exposicion.
/// - `iso`: la sensibilidad ISO (EXIF ISOSpeed).
/// - `balance_blancos`: `"auto"` o `"manual"`, segun EXIF WhiteBalance. Ese tag
///   solo distingue esos dos modos; no dice la temperatura de color.
///
/// **No verificado en un telefono**: que el EXIF de la camara frontal de Android
/// y de iOS traiga estos tags.
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:wearhack/features/captura_pruebas/metadatos.dart';

const int _tagExposureTime = 0x829a;
const int _tagIsoSpeed = 0x8827;
const int _tagWhiteBalance = 0xa403;

/// Lee los parametros del EXIF de [jpeg]. Nunca lanza: un EXIF ilegible o sin
/// esos tags da parametros vacios.
ParametrosDeCamara leerParametrosDeCamara(Uint8List jpeg) {
  try {
    final img.ExifData? exif = img.decodeJpgExif(jpeg);
    if (exif == null) return const ParametrosDeCamara();
    final img.IfdDirectory datos = exif.exifIfd;

    final img.IfdValue? exposicion = datos[_tagExposureTime];
    final img.IfdValue? iso = datos[_tagIsoSpeed];
    final img.IfdValue? balance = datos[_tagWhiteBalance];

    final double? segundos = exposicion?.toDouble();
    return ParametrosDeCamara(
      exposicion: (segundos != null && segundos.isFinite && segundos > 0)
          ? segundos
          : null,
      iso: (iso != null && iso.toInt() > 0) ? iso.toInt() : null,
      balanceBlancos: switch (balance?.toInt()) {
        0 => 'auto',
        1 => 'manual',
        _ => null,
      },
    );
  } on Object {
    return const ParametrosDeCamara();
  }
}
