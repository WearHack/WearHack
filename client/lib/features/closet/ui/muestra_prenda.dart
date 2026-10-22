/// Miniatura de una prenda: su color y el icono de su slot.
///
/// Ocupa el lugar de la imagen procesada mientras no exista. Cuando llegue,
/// solo cambia este widget.
library;

import 'package:flutter/material.dart';
import 'package:wearhack/core/ui/etiquetas.dart';
import 'package:wearhack/core/vocabulario.dart';
import 'package:wearhack/features/closet/prenda.dart';

class MuestraPrenda extends StatelessWidget {
  const MuestraPrenda({super.key, required this.prenda, this.tamano});

  final Prenda prenda;

  /// Lado del cuadrado. Sin tamano ocupa todo el espacio que le den.
  final double? tamano;

  @override
  Widget build(BuildContext context) {
    final Color fondo = prenda.categoriaColor.muestra;
    final bool multicolor = prenda.categoriaColor == CategoriaColor.multicolor;
    // El icono tiene que leerse igual sobre blanco que sobre negro.
    final Color frente = fondo.computeLuminance() > 0.5
        ? Colors.black87
        : Colors.white;

    final Widget caja = Tooltip(
      message: '${prenda.tipo.etiqueta} ${prenda.categoriaColor.etiqueta}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: multicolor ? null : fondo,
          gradient: multicolor
              ? const LinearGradient(
                  colors: <Color>[
                    Color(0xFFC62828),
                    Color(0xFFF9A825),
                    Color(0xFF2E7D32),
                    Color(0xFF1565C0),
                  ],
                )
              : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Center(
          child: Icon(
            prenda.slot.icono,
            color: frente,
            size: tamano == null ? 48 : tamano! * 0.5,
          ),
        ),
      ),
    );

    return tamano == null
        ? caja
        : SizedBox.square(dimension: tamano, child: caja);
  }
}
