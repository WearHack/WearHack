/// Por que se recomienda una prenda puente: que combinaciones abre con lo que
/// el usuario ya tiene.
library;

import 'package:flutter/material.dart';
import 'package:wearhack/core/ui/etiquetas.dart';
import 'package:wearhack/core/ui/formato.dart';
import 'package:wearhack/features/closet/prenda.dart';
import 'package:wearhack/features/closet/ui/muestra_prenda.dart';
import 'package:wearhack/features/outfits/contexto.dart';
import 'package:wearhack/features/outfits/outfit.dart';
import 'package:wearhack/features/outfits/ui/tarjeta_outfit.dart';
import 'package:wearhack/features/publicidad/catalogo.dart';

class PantallaPrendaPuente extends StatelessWidget {
  const PantallaPrendaPuente({super.key, required this.puente});

  final PrendaPuente puente;

  @override
  Widget build(BuildContext context) {
    final TextTheme texto = Theme.of(context).textTheme;
    final ColorScheme colores = Theme.of(context).colorScheme;
    final ProductoCatalogo producto = puente.producto;
    final Prenda prenda = producto.prenda;

    return Scaffold(
      appBar: AppBar(title: Text(producto.nombre)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Row(
                children: <Widget>[
                  MuestraPrenda(prenda: prenda, tamano: 96),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(producto.nombre, style: texto.titleLarge),
                        Text(producto.marca.nombre, style: texto.bodyMedium),
                        const SizedBox(height: 4),
                        Text(
                          formatoPesos(producto.precioPesos),
                          style: texto.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${prenda.slot.etiqueta} · '
                          '${prenda.categoriaColor.etiqueta} · '
                          '${prenda.formalidad.etiqueta}',
                          style: texto.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Card(
                color: colores.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Abre ${puente.combinacionesBuenas} combinaciones '
                        'nuevas con lo que ya tienes',
                        style: texto.titleMedium,
                      ),
                      if (puente.ocasionesNuevas.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          'Y te permite vestirte para algo que hoy no puedes '
                          'cubrir con tu clóset:',
                          style: texto.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: <Widget>[
                            for (final Ocasion o in puente.ocasionesNuevas)
                              Chip(
                                avatar: const Icon(Icons.event_available),
                                label: Text(o.etiqueta),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (puente.ejemplos.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                Text('Algunas de esas combinaciones', style: texto.titleSmall),
                for (final Outfit o in puente.ejemplos) ...<Widget>[
                  const SizedBox(height: 8),
                  TarjetaOutfit(outfit: o),
                ],
              ],
              const SizedBox(height: 16),
              Text(
                'Contenido de una marca aliada. Las combinaciones se calculan '
                'con tu clóset.',
                style: texto.bodySmall?.copyWith(
                  color: colores.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
