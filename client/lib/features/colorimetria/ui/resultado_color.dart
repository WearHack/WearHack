/// Lo que se ve del resultado de la colorimetria: el anillo de confianza y los
/// colores que se midieron en la cara.
///
/// Las muestras son **los colores de la persona** (piel, cabello, iris) tal
/// como los midio el servicio, no la paleta recomendada de su temporada: esa
/// todavia no llega del Core.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wearhack/core/color/conversion.dart';
import 'package:wearhack/core/ui/movimiento.dart';
import 'package:wearhack/core/vocabulario.dart';

/// Un anillo que se llena hasta [valor] (de 0 a 1) con el porcentaje en el
/// centro contando desde cero. Con "reducir animaciones" aparece ya lleno.
class AnilloConfianza extends StatelessWidget {
  const AnilloConfianza({super.key, required this.valor, this.tamano = 88});

  final double valor;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;
    final double objetivo = valor.clamp(0.0, 1.0).toDouble();
    final bool quieto = MediaQuery.disableAnimationsOf(context);

    // El texto de al lado ya dice la confianza con palabras: el anillo es
    // solo la version visual y no se lee dos veces.
    return ExcludeSemantics(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: quieto ? objetivo : 0, end: objetivo),
        duration: quieto ? Duration.zero : const Duration(milliseconds: 1000),
        curve: Curves.easeOutCubic,
        builder: (BuildContext context, double t, Widget? _) => SizedBox.square(
          dimension: tamano,
          child: CustomPaint(
            painter: _PintorAnillo(
              avance: t,
              pista: colores.surfaceContainerHighest,
              trazo: colores.primary,
            ),
            child: Center(
              child: Text(
                '${(t * 100).round()} %',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PintorAnillo extends CustomPainter {
  const _PintorAnillo({
    required this.avance,
    required this.pista,
    required this.trazo,
  });

  final double avance;
  final Color pista;
  final Color trazo;

  @override
  void paint(Canvas canvas, Size size) {
    const double grosor = 9;
    final Rect marco = Offset.zero & size;
    final Rect area = marco.deflate(grosor / 2);
    final Paint base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = grosor
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(area, 0, 2 * math.pi, false, base..color = pista);
    if (avance > 0) {
      canvas.drawArc(
        area,
        -math.pi / 2,
        2 * math.pi * avance,
        false,
        base..color = trazo,
      );
    }
  }

  @override
  bool shouldRepaint(_PintorAnillo anterior) =>
      anterior.avance != avance ||
      anterior.pista != pista ||
      anterior.trazo != trazo;
}

/// Piel, cabello e iris como tres muestras grandes que entran una tras otra.
/// Las que el servicio no pudo medir no se dibujan.
class MuestrasPerfil extends StatelessWidget {
  const MuestrasPerfil({super.key, this.piel, this.cabello, this.iris});

  final ColorLab? piel;
  final ColorLab? cabello;
  final ColorLab? iris;

  static Color aColor(ColorLab lab) {
    final ({int r, int g, int b}) c = labASrgb8(lab);
    return Color.fromARGB(255, c.r, c.g, c.b);
  }

  @override
  Widget build(BuildContext context) {
    final List<(String, ColorLab)> medidas = <(String, ColorLab)>[
      if (piel != null) ('Piel', piel!),
      if (cabello != null) ('Cabello', cabello!),
      if (iris != null) ('Ojos', iris!),
    ];
    if (medidas.isEmpty) return const SizedBox.shrink();

    final TextTheme texto = Theme.of(context).textTheme;
    final Color borde = Theme.of(context).colorScheme.outlineVariant;

    return Row(
      children: <Widget>[
        for (final (int i, (String, ColorLab) m)
            in medidas.indexed) ...<Widget>[
          if (i > 0) const SizedBox(width: 12),
          Expanded(
            child: Aparece(
              indice: i + 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: aColor(m.$2),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borde),
                    ),
                    child: const SizedBox(height: 72),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    m.$1,
                    style: texto.labelMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
