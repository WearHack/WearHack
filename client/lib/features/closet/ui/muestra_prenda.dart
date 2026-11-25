/// Miniatura de una prenda: su color y el icono de su slot.
///
/// Ocupa el lugar de la imagen procesada mientras no exista. Cuando llegue,
/// solo cambia este widget.
library;

import 'package:flutter/material.dart';
import 'package:wearhack/core/ui/etiquetas.dart';
import 'package:wearhack/core/vocabulario.dart';
import 'package:wearhack/features/closet/prenda.dart';
import 'package:wearhack/features/closet/ui/silueta_prenda.dart';

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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
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
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            // La silueta ocupa algo mas de la mitad de la muestra, sea del
            // tamano que sea.
            final double lado = tamano != null
                ? tamano! * 0.62
                : (c.biggest.shortestSide.isFinite
                          ? c.biggest.shortestSide
                          : 96) *
                      0.58;
            return Center(
              child: SiluetaPrenda(
                tipo: prenda.tipo,
                color: frente,
                fondo: multicolor ? const Color(0xFF1565C0) : fondo,
                tamano: lado,
              ),
            );
          },
        ),
      ),
    );

    final String? url = prenda.imagenUrl;
    final Widget muestra = url == null
        ? caja
        : Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => caja,
          );
    return tamano == null
        ? muestra
        : SizedBox.square(dimension: tamano, child: muestra);
  }
}
