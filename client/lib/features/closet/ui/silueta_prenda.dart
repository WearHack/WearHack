/// La silueta de una prenda, dibujada.
///
/// Material no trae iconos de camiseta, pantalon ni zapato, y con el mismo
/// gancho para todo lo superior un closet de 15 prendas se ve repetido. Estas
/// siluetas son formas simples en una caja de 100 x 100: ocupan el lugar de la
/// imagen procesada hasta que exista.
///
/// El accesorio no tiene silueta propia (es de todo: reloj, bolso, gafas) y
/// sigue usando el icono.
library;

import 'package:flutter/material.dart';
import 'package:wearhack/core/vocabulario.dart';

class SiluetaPrenda extends StatelessWidget {
  const SiluetaPrenda({
    super.key,
    required this.tipo,
    required this.color,
    required this.fondo,
    required this.tamano,
  });

  final TipoPrenda tipo;

  /// El color de la silueta.
  final Color color;

  /// El color sobre el que se dibuja. Las costuras (la abertura de una
  /// chaqueta, la cintura de un pantalon) se pintan con el, para que parezcan
  /// huecos.
  final Color fondo;

  final double tamano;

  @override
  Widget build(BuildContext context) {
    if (tipo == TipoPrenda.accesorio) {
      return Icon(Icons.watch, color: color, size: tamano);
    }
    return SizedBox.square(
      dimension: tamano,
      child: CustomPaint(painter: _Pintor(tipo, color, fondo)),
    );
  }
}

class _Pintor extends CustomPainter {
  const _Pintor(this.tipo, this.color, this.fondo);

  final TipoPrenda tipo;
  final Color color;
  final Color fondo;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 100);
    final Paint relleno = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true
      ..color = color;
    final Paint costura = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true
      ..color = fondo;

    canvas.drawPath(forma(tipo), relleno);

    switch (tipo) {
      case TipoPrenda.chaqueta || TipoPrenda.abrigo:
        // La abertura del frente.
        canvas.drawLine(
          const Offset(50, 16),
          Offset(50, _largo(tipo)),
          costura,
        );
      case TipoPrenda.camisa:
        canvas.drawLine(const Offset(50, 18), const Offset(50, 88), costura);
      case TipoPrenda.pantalon || TipoPrenda.jean:
        // La cintura.
        canvas.drawLine(const Offset(28, 17), const Offset(72, 17), costura);
      case TipoPrenda.zapato || TipoPrenda.tenis || TipoPrenda.sandalia:
        // La suela.
        canvas.drawLine(const Offset(9, 71), const Offset(92, 71), costura);
      case TipoPrenda.bota:
        canvas.drawLine(const Offset(11, 71), const Offset(92, 71), costura);
      case _:
        break;
    }
  }

  @override
  bool shouldRepaint(_Pintor anterior) =>
      anterior.tipo != tipo ||
      anterior.color != color ||
      anterior.fondo != fondo;

  static double _largo(TipoPrenda tipo) => tipo == TipoPrenda.abrigo ? 94 : 88;

  /// La forma de cada tipo en una caja de 100 x 100. Publica para probarla.
  static Path forma(TipoPrenda tipo) => switch (tipo) {
    TipoPrenda.camiseta => _camiseta(),
    TipoPrenda.camisa ||
    TipoPrenda.blusa ||
    TipoPrenda.sueter ||
    TipoPrenda.chaqueta => _mangaLarga(largo: 88),
    TipoPrenda.abrigo => _mangaLarga(largo: 94),
    TipoPrenda.pantalon || TipoPrenda.jean => _pantalon(),
    TipoPrenda.short => _short(),
    TipoPrenda.falda => _falda(),
    TipoPrenda.vestido => _vestido(),
    TipoPrenda.bota => _bota(),
    TipoPrenda.zapato || TipoPrenda.tenis || TipoPrenda.sandalia => _zapato(),
    TipoPrenda.accesorio => Path(),
  };

  static Path _camiseta() => Path()
    ..moveTo(30, 14)
    ..lineTo(41, 14)
    ..quadraticBezierTo(50, 26, 59, 14)
    ..lineTo(70, 14)
    ..lineTo(93, 30)
    ..lineTo(82, 47)
    ..lineTo(72, 40)
    ..lineTo(72, 88)
    ..lineTo(28, 88)
    ..lineTo(28, 40)
    ..lineTo(18, 47)
    ..lineTo(7, 30)
    ..close();

  static Path _mangaLarga({required double largo}) => Path()
    ..moveTo(32, 12)
    ..lineTo(42, 12)
    ..quadraticBezierTo(50, 22, 58, 12)
    ..lineTo(68, 12)
    ..lineTo(90, 26)
    ..lineTo(86, 78)
    ..lineTo(74, 78)
    ..lineTo(72, 40)
    ..lineTo(72, largo)
    ..lineTo(28, largo)
    ..lineTo(28, 40)
    ..lineTo(26, 78)
    ..lineTo(14, 78)
    ..lineTo(10, 26)
    ..close();

  static Path _pantalon() => Path()
    ..moveTo(28, 10)
    ..lineTo(72, 10)
    ..lineTo(77, 92)
    ..lineTo(55, 92)
    ..lineTo(50, 36)
    ..lineTo(45, 92)
    ..lineTo(23, 92)
    ..close();

  static Path _short() => Path()
    ..moveTo(26, 18)
    ..lineTo(74, 18)
    ..lineTo(81, 64)
    ..lineTo(55, 64)
    ..lineTo(50, 40)
    ..lineTo(45, 64)
    ..lineTo(19, 64)
    ..close();

  static Path _falda() => Path()
    ..moveTo(35, 14)
    ..lineTo(65, 14)
    ..lineTo(86, 86)
    ..quadraticBezierTo(50, 94, 14, 86)
    ..close();

  static Path _vestido() => Path()
    ..moveTo(37, 8)
    ..lineTo(45, 8)
    ..quadraticBezierTo(50, 17, 55, 8)
    ..lineTo(63, 8)
    ..lineTo(65, 36)
    ..lineTo(84, 90)
    ..quadraticBezierTo(50, 97, 16, 90)
    ..lineTo(35, 36)
    ..close();

  static Path _zapato() => Path()
    ..moveTo(9, 40)
    ..lineTo(27, 40)
    ..quadraticBezierTo(31, 56, 46, 58)
    ..lineTo(62, 50)
    ..quadraticBezierTo(72, 50, 79, 59)
    ..quadraticBezierTo(93, 62, 93, 75)
    ..lineTo(93, 82)
    ..lineTo(9, 82)
    ..close();

  static Path _bota() => Path()
    ..moveTo(25, 10)
    ..lineTo(55, 10)
    ..lineTo(56, 46)
    ..quadraticBezierTo(80, 52, 91, 64)
    ..lineTo(93, 82)
    ..lineTo(11, 82)
    ..lineTo(13, 58)
    ..lineTo(25, 52)
    ..close();
}

/// La forma de [tipo] en una caja de 100 x 100, para probar que cada tipo
/// tiene la suya.
Path formaDeSilueta(TipoPrenda tipo) => _Pintor.forma(tipo);
