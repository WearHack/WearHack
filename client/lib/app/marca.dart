/// La marca de WearHack: el gancho con la W, dibujado en vectores a partir del
/// logo del proyecto.
///
/// Se dibuja y no se carga como imagen para que se vea nitido a cualquier
/// tamano y sobre el fondo claro y el oscuro (el logo en PNG trae fondo crema).
/// Es una version simplificada: cuando haya un SVG oficial se cambia aqui y en
/// ningun otro sitio.
library;

import 'package:flutter/material.dart';

class MarcaWearHack extends StatelessWidget {
  const MarcaWearHack({super.key, this.alto = 40});

  /// Alto de la marca. El ancho sale de la proporcion del dibujo.
  final double alto;

  /// Ancho entre alto del dibujo.
  static const double proporcion = 1.36;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'WearHack',
      image: true,
      child: ExcludeSemantics(
        child: CustomPaint(
          size: Size(alto * proporcion, alto),
          painter: const _PintorMarca(),
        ),
      ),
    );
  }
}

class _PintorMarca extends CustomPainter {
  const _PintorMarca();

  static const Color _terracota = Color(0xFFC9553D);
  static const Color _naranja = Color(0xFFD9803C);
  static const Color _ocre = Color(0xFFE3A12F);
  static const Color _arena = Color(0xFFD8B88A);

  @override
  void paint(Canvas canvas, Size size) {
    // El dibujo vive en una caja de 136 x 100.
    canvas.scale(size.height / 100);
    final Paint trazo = Paint()
      ..style = PaintingStyle.stroke
      // En tamanos chicos el trazo se engrosa, o la W se pierde.
      ..strokeWidth = size.height < 44 ? 7 : 5.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    // El gancho y el brazo izquierdo.
    final Path izquierdo = Path()
      ..moveTo(55, 19)
      ..cubicTo(55, 3, 78, 3, 78, 17)
      ..cubicTo(78, 24, 68, 25, 67, 32)
      ..lineTo(12, 58)
      ..quadraticBezierTo(2, 63, 6, 70)
      ..quadraticBezierTo(9, 75, 18, 75)
      ..lineTo(30, 75);
    canvas.drawPath(izquierdo, trazo..color = _terracota);

    // El brazo derecho, cortado en dos tramos como en el logo.
    final Path derecho = Path()
      ..moveTo(111, 54)
      ..lineTo(124, 58)
      ..quadraticBezierTo(134, 62, 131, 70)
      ..quadraticBezierTo(128, 75, 118, 75)
      ..lineTo(103, 75);
    canvas.drawPath(derecho, trazo..color = _arena);

    canvas.drawLine(
      const Offset(73, 34),
      const Offset(97, 47),
      trazo..color = _ocre,
    );

    // La W, con un degradado de terracota a naranja.
    final Path w = Path()
      ..moveTo(34, 63)
      ..lineTo(45, 98)
      ..lineTo(60, 68)
      ..lineTo(74, 98)
      ..lineTo(108, 39);
    canvas.drawPath(
      w,
      trazo
        ..shader = const LinearGradient(colors: <Color>[_terracota, _naranja])
            .createShader(const Rect.fromLTWH(34, 39, 74, 59)),
    );
  }

  @override
  bool shouldRepaint(_PintorMarca anterior) => false;
}
