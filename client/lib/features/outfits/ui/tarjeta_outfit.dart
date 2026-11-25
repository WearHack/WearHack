/// Un outfit en una tarjeta: sus prendas, su formalidad y su clima.
library;

import 'package:flutter/material.dart';
import 'package:wearhack/core/ui/etiquetas.dart';
import 'package:wearhack/core/vocabulario.dart';
import 'package:wearhack/features/closet/prenda.dart';
import 'package:wearhack/features/closet/ui/muestra_prenda.dart';
import 'package:wearhack/features/outfits/outfit.dart';

String etiquetaOutfit(Outfit outfit) => switch (outfit.clima) {
  final Clima clima => '${outfit.formalidad.etiqueta} · ${clima.etiqueta}',
  null => outfit.formalidad.etiqueta,
};

class TarjetaOutfit extends StatelessWidget {
  const TarjetaOutfit({
    super.key,
    required this.outfit,
    this.onTap,
    this.seleccionado = false,
  });

  final Outfit outfit;
  final VoidCallback? onTap;

  /// Lo resalta, para cuando se elige entre varios.
  final bool seleccionado;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;
    final List<Prenda> prendas = outfit.prendasEnOrden;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: seleccionado
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: colores.primary, width: 2),
            )
          : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  if (outfit.clima case final Clima clima) ...<Widget>[
                    Icon(clima.icono, size: 18),
                    const SizedBox(width: 6),
                  ],
                  // Expanded y no Spacer: con tres tarjetas lado a lado el
                  // texto no siempre cabe, y sin limite desborda la fila.
                  Expanded(
                    child: Text(
                      etiquetaOutfit(outfit),
                      style: Theme.of(context).textTheme.labelLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (seleccionado)
                    // Aparece con un pequeno rebote: confirma la eleccion.
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutBack,
                      builder: (BuildContext context, double t, Widget? hijo) =>
                          Transform.scale(scale: t, child: hijo),
                      child: Icon(Icons.check_circle, color: colores.primary),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final Prenda p in prendas)
                    MuestraPrenda(prenda: p, tamano: 56),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                prendas.map((Prenda p) => p.tipo.etiqueta).join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
