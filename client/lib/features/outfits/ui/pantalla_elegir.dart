/// Elegir el mejor de N: el outfit de hoy entre las opciones del motor.
///
/// Issue #16. La eleccion es la senal de aprendizaje, asi que aqui no hay "me
/// gusta" ni valoraciones. Por la misma razon se elige en dos pasos, marcar y
/// confirmar: un toque accidental entrenaria las preferencias con ruido.
library;

import 'package:flutter/material.dart';
import 'package:wearhack/features/outfits/outfit.dart';
import 'package:wearhack/features/outfits/repositorio_outfits.dart';
import 'package:wearhack/features/outfits/ui/tarjeta_outfit.dart';

/// Devuelve `true` al cerrarse si se registro una eleccion.
class PantallaElegir extends StatefulWidget {
  const PantallaElegir({
    super.key,
    required this.repositorio,
    required this.lote,
  });

  final RepositorioOutfits repositorio;
  final LoteOpciones lote;

  @override
  State<PantallaElegir> createState() => _PantallaElegirState();
}

class _PantallaElegirState extends State<PantallaElegir> {
  /// Por encima de este ancho las opciones van lado a lado.
  static const double _anchoEnFila = 720;

  String? _marcado;
  bool _guardando = false;

  Future<void> _confirmar() async {
    setState(() => _guardando = true);
    try {
      await widget.repositorio.elegir(widget.lote.id, _marcado!);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on Object {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo guardar tu elección. Inténtalo de nuevo.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> tarjetas = <Widget>[
      for (final Outfit o in widget.lote.opciones)
        TarjetaOutfit(
          outfit: o,
          seleccionado: o.id == _marcado,
          onTap: _guardando ? null : () => setState(() => _marcado = o.id),
        ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Elige tu outfit de hoy')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Text(
                'Toca el que más te guste y confírmalo. Con cada elección '
                'aprendemos tu estilo y las próximas opciones se parecen más '
                'a ti.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              if (MediaQuery.sizeOf(context).width >= _anchoEnFila)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (int i = 0; i < tarjetas.length; i++) ...<Widget>[
                      if (i > 0) const SizedBox(width: 12),
                      Expanded(child: tarjetas[i]),
                    ],
                  ],
                )
              else
                for (final Widget t in tarjetas)
                  Padding(padding: const EdgeInsets.only(bottom: 8), child: t),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _marcado == null || _guardando ? null : _confirmar,
            child: _guardando
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Usar este outfit'),
          ),
        ),
      ),
    );
  }
}
