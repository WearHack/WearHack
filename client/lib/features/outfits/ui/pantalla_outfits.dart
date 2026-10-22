/// Los outfits que el recomendador genero para esta semana.
///
/// Arriba, la entrada a elegir el outfit de hoy entre N opciones (issue #16);
/// debajo, la consulta de los outfits de la semana (issue #15).
library;

import 'package:flutter/material.dart';
import 'package:wearhack/core/ui/estados.dart';
import 'package:wearhack/core/ui/etiquetas.dart';
import 'package:wearhack/features/closet/prenda.dart';
import 'package:wearhack/features/closet/ui/muestra_prenda.dart';
import 'package:wearhack/features/outfits/outfit.dart';
import 'package:wearhack/features/outfits/repositorio_outfits.dart';
import 'package:wearhack/features/outfits/ui/pantalla_elegir.dart';
import 'package:wearhack/features/outfits/ui/tarjeta_outfit.dart';

class PantallaOutfits extends StatefulWidget {
  const PantallaOutfits({super.key, required this.repositorio});

  final RepositorioOutfits repositorio;

  @override
  State<PantallaOutfits> createState() => _PantallaOutfitsState();
}

class _PantallaOutfitsState extends State<PantallaOutfits> {
  late Future<(List<Outfit>, LoteOpciones)> _carga = _cargar();

  Future<(List<Outfit>, LoteOpciones)> _cargar() async => (
    await widget.repositorio.outfitsDeLaSemana(),
    await widget.repositorio.opcionesDeHoy(),
  );

  void _recargar() {
    setState(() {
      _carga = _cargar();
    });
  }

  Future<void> _elegir(LoteOpciones lote) async {
    final bool? eligio = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            PantallaElegir(repositorio: widget.repositorio, lote: lote),
      ),
    );
    if (eligio != true || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Listo, ese es tu outfit de hoy')),
    );
    _recargar();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(List<Outfit>, LoteOpciones)>(
      future: _carga,
      builder:
          (
            BuildContext context,
            AsyncSnapshot<(List<Outfit>, LoteOpciones)> snapshot,
          ) {
            if (snapshot.hasError) return ErrorDeCarga(onReintentar: _recargar);
            final (List<Outfit>, LoteOpciones)? datos = snapshot.data;
            if (datos == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final (List<Outfit> outfits, LoteOpciones lote) = datos;
            if (outfits.isEmpty) {
              return const MensajeVacio(
                icono: Icons.style_outlined,
                texto: 'Todavía no hay outfits para esta semana.',
              );
            }

            // En web la ventana puede ser muy ancha; una columna de tarjetas
            // estiradas a 1900 px no se lee.
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    // Con menos de dos opciones no hay nada que comparar, y
                    // una eleccion sin descartados no ensena nada.
                    if (lote.elegidoId != null || lote.opciones.length >= 2)
                      _OutfitDeHoy(lote: lote, onElegir: () => _elegir(lote)),
                    const SizedBox(height: 16),
                    Text(
                      'Generados a partir de tu clóset para esta semana.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    for (final Outfit o in outfits) ...<Widget>[
                      const SizedBox(height: 8),
                      TarjetaOutfit(outfit: o),
                    ],
                  ],
                ),
              ),
            );
          },
    );
  }
}

class _OutfitDeHoy extends StatelessWidget {
  const _OutfitDeHoy({required this.lote, required this.onElegir});

  final LoteOpciones lote;
  final VoidCallback onElegir;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;
    final TextTheme texto = Theme.of(context).textTheme;
    final Outfit? elegido = lote.elegido;

    return Card(
      color: colores.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: lote.elegidoId == null
            ? Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('¿Qué te pones hoy?', style: texto.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          'Elige entre ${lote.opciones.length} opciones '
                          'pensadas para ti.',
                          style: texto.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: onElegir,
                    child: const Text('Elegir'),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Tu outfit de hoy', style: texto.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Ya elegiste el outfit de hoy.',
                    style: texto.bodyMedium,
                  ),
                  // Puede faltar si despues se elimino una de sus prendas.
                  if (elegido != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[
                        for (final Prenda p in elegido.prendasEnOrden)
                          MuestraPrenda(prenda: p, tamano: 40),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      elegido.prendasEnOrden
                          .map((Prenda p) => p.tipo.etiqueta)
                          .join(' · '),
                      style: texto.bodySmall,
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
