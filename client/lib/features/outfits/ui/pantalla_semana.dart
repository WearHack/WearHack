/// La semana en curso, un outfit por dia.
///
/// La parte de gestion de la issue #15: tocar un dia permite cambiar su outfit
/// por otro de los generados o dejarlo libre.
library;

import 'package:flutter/material.dart';
import 'package:wearhack/core/ui/estados.dart';
import 'package:wearhack/features/closet/prenda.dart';
import 'package:wearhack/features/closet/ui/muestra_prenda.dart';
import 'package:wearhack/features/outfits/outfit.dart';
import 'package:wearhack/features/outfits/repositorio_outfits.dart';
import 'package:wearhack/features/outfits/ui/tarjeta_outfit.dart';

const List<String> _dias = <String>[
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];

const List<String> _meses = <String>[
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

String _fechaCorta(DateTime d) => '${d.day} ${_meses[d.month - 1]}';

class PantallaSemana extends StatefulWidget {
  const PantallaSemana({super.key, required this.repositorio});

  final RepositorioOutfits repositorio;

  @override
  State<PantallaSemana> createState() => _PantallaSemanaState();
}

class _PantallaSemanaState extends State<PantallaSemana> {
  late Future<List<DiaPlan>> _carga = widget.repositorio.planSemanal();

  void _recargar() {
    setState(() {
      _carga = widget.repositorio.planSemanal();
    });
  }

  Future<void> _cambiar(DiaPlan dia) async {
    final List<Outfit> outfits;
    try {
      outfits = await widget.repositorio.outfitsDeLaSemana();
    } on Exception {
      _mostrarError('No se pudieron cargar los outfits.');
      return;
    }
    if (!mounted) return;

    // Un record y no un String? a secas: hay que distinguir "dejar libre"
    // (id nulo) de cerrar la hoja sin elegir (resultado nulo).
    final ({String? id})? eleccion = await showModalBottomSheet<({String? id})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SelectorOutfit(dia: dia, outfits: outfits),
    );
    if (eleccion == null || !mounted) return;

    try {
      await widget.repositorio.asignarOutfit(dia.fecha, eleccion.id);
    } on Exception {
      _mostrarError('No se pudo actualizar el día.');
      return;
    }
    if (!mounted) return;
    _recargar();
  }

  void _mostrarError(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DiaPlan>>(
      future: _carga,
      builder: (BuildContext context, AsyncSnapshot<List<DiaPlan>> snapshot) {
        if (snapshot.hasError) return ErrorDeCarga(onReintentar: _recargar);
        final List<DiaPlan>? plan = snapshot.data;
        if (plan == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Text(
                  'Semana del ${_fechaCorta(plan.first.fecha)} '
                  'al ${_fechaCorta(plan.last.fecha)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final DiaPlan dia in plan)
                  _FilaDia(dia: dia, onTap: () => _cambiar(dia)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FilaDia extends StatelessWidget {
  const _FilaDia({required this.dia, required this.onTap});

  final DiaPlan dia;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;
    final TextTheme texto = Theme.of(context).textTheme;
    final bool esHoy = DateUtils.isSameDay(dia.fecha, DateTime.now());
    final Outfit? outfit = dia.outfit;

    return Card(
      color: esHoy ? colores.primaryContainer : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 96,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(_dias[dia.fecha.weekday - 1], style: texto.titleSmall),
                    Text(
                      esHoy ? 'Hoy' : _fechaCorta(dia.fecha),
                      style: texto.bodySmall,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: outfit == null
                    ? Text(
                        'Sin outfit · toca para elegir uno',
                        style: texto.bodyMedium?.copyWith(
                          color: colores.onSurfaceVariant,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: <Widget>[
                              for (final Prenda p in outfit.prendasEnOrden)
                                MuestraPrenda(prenda: p, tamano: 40),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(etiquetaOutfit(outfit), style: texto.bodySmall),
                        ],
                      ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectorOutfit extends StatelessWidget {
  const _SelectorOutfit({required this.dia, required this.outfits});

  final DiaPlan dia;
  final List<Outfit> outfits;

  @override
  Widget build(BuildContext context) {
    final String? actual = dia.outfit?.id;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Outfit del ${_dias[dia.fecha.weekday - 1].toLowerCase()}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (actual != null)
                    TextButton.icon(
                      onPressed: () =>
                          Navigator.of(context).pop<({String? id})>((id: null)),
                      icon: const Icon(Icons.event_busy),
                      label: const Text('Dejar el día libre'),
                    ),
                ],
              ),
            ),
            Flexible(
              child: outfits.isEmpty
                  ? const MensajeVacio(
                      icono: Icons.style_outlined,
                      texto: 'No hay outfits generados para elegir.',
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(16),
                      itemCount: outfits.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (BuildContext context, int i) =>
                          TarjetaOutfit(
                            outfit: outfits[i],
                            seleccionado: outfits[i].id == actual,
                            onTap: () =>
                                Navigator.of(context)
                                    .pop<({String? id})>((id: outfits[i].id)),
                          ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
