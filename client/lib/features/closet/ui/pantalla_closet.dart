/// El closet: todas las prendas, filtrables por slot.
///
/// Solo consulta y gestion (issue #15). Agregar prendas pide la camara y el
/// pipeline on-device, que en web no existen: el boton lo pone
/// `PantallaPrincipal` solo donde hay captura (#11).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wearhack/core/ui/estados.dart';
import 'package:wearhack/core/ui/etiquetas.dart';
import 'package:wearhack/core/ui/movimiento.dart';
import 'package:wearhack/core/vocabulario.dart';
import 'package:wearhack/features/closet/prenda.dart';
import 'package:wearhack/features/closet/repositorio_closet.dart';
import 'package:wearhack/features/closet/ui/muestra_prenda.dart';

class PantallaCloset extends StatefulWidget {
  const PantallaCloset({super.key, required this.repositorio, this.subidas});

  final RepositorioCloset repositorio;
  final Stream<void>? subidas;

  @override
  State<PantallaCloset> createState() => _PantallaClosetState();
}

class _PantallaClosetState extends State<PantallaCloset> {
  late Future<List<Prenda>> _carga = widget.repositorio.prendas();
  StreamSubscription<void>? _subidas;

  @override
  void initState() {
    super.initState();
    _subidas = widget.subidas?.listen((_) => _recargar());
  }

  @override
  void dispose() {
    unawaited(_subidas?.cancel());
    super.dispose();
  }

  /// `null` muestra todas.
  SlotOutfit? _filtro;
  final Set<String> _borrando = <String>{};

  /// Las prendas que ya entraron con animacion: al desplazarse o filtrar, lo
  /// que ya se vio no vuelve a entrar.
  final Set<String> _vistas = <String>{};

  void _recargar() {
    setState(() {
      _carga = widget.repositorio.prendas();
    });
  }

  Future<void> _abrir(Prenda prenda) async {
    if (_borrando.contains(prenda.id)) return;
    final RepositorioCloset repositorio = widget.repositorio;
    final bool? eliminar = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DetallePrenda(
        prenda: prenda,
        permiteBorrar: repositorio is ClosetConBorrado,
      ),
    );
    if (eliminar != true || !mounted || repositorio is! ClosetConBorrado) {
      return;
    }

    final bool? confirmado = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('¿Eliminar ${_tipo(prenda).toLowerCase()}?'),
        content: const Text('La prenda y su imagen se eliminarán del clóset.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted || !_borrando.add(prenda.id)) return;

    try {
      await repositorio.eliminarPrenda(prenda.id);
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo eliminar la prenda')),
        );
      }
      return;
    } finally {
      _borrando.remove(prenda.id);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Prenda eliminada del clóset')),
    );
    _recargar();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Prenda>>(
      future: _carga,
      builder: (BuildContext context, AsyncSnapshot<List<Prenda>> snapshot) {
        if (snapshot.hasError) return ErrorDeCarga(onReintentar: _recargar);
        final List<Prenda>? prendas = snapshot.data;
        if (prendas == null) {
          return const EsqueletoCuadricula();
        }
        if (prendas.isEmpty) {
          return const MensajeVacio(
            icono: Icons.checkroom_outlined,
            texto: 'Tu clóset está vacío. Agrega prendas desde la app móvil.',
          );
        }

        final List<Prenda> visibles = <Prenda>[
          for (final Prenda p in prendas)
            if (_filtro == null || p.slot == _filtro) p,
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Filtros(
              seleccionado: _filtro,
              onCambio: (SlotOutfit? slot) => setState(() => _filtro = slot),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                visibles.length == 1
                    ? '1 prenda'
                    : '${visibles.length} prendas',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            Expanded(
              child: visibles.isEmpty
                  ? const MensajeVacio(
                      icono: Icons.filter_alt_off_outlined,
                      texto: 'No tienes prendas en esta categoría.',
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 180,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.8,
                          ),
                      itemCount: visibles.length,
                      itemBuilder: (BuildContext context, int i) {
                        final Prenda p = visibles[i];
                        return Aparece(
                          key: ValueKey<String>(p.id),
                          indice: i,
                          animar: _vistas.add(p.id),
                          child: _TarjetaPrenda(
                            prenda: p,
                            onTap: () => _abrir(p),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _Filtros extends StatelessWidget {
  const _Filtros({required this.seleccionado, required this.onCambio});

  final SlotOutfit? seleccionado;
  final ValueChanged<SlotOutfit?> onCambio;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: <Widget>[
          ChoiceChip(
            label: const Text('Todas'),
            selected: seleccionado == null,
            onSelected: (_) => onCambio(null),
          ),
          for (final SlotOutfit slot in SlotOutfit.values) ...<Widget>[
            const SizedBox(width: 8),
            ChoiceChip(
              label: Text(slot.etiqueta),
              selected: seleccionado == slot,
              onSelected: (_) => onCambio(slot),
            ),
          ],
        ],
      ),
    );
  }
}

class _TarjetaPrenda extends StatelessWidget {
  const _TarjetaPrenda({required this.prenda, required this.onTap});

  final Prenda prenda;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme texto = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: MuestraPrenda(prenda: prenda)),
              const SizedBox(height: 8),
              Text(_tipo(prenda), style: texto.titleSmall),
              Text(
                '${prenda.categoriaColor.etiqueta} · ${prenda.patron.etiqueta}',
                style: texto.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La ficha de una prenda. Devuelve `true` si el usuario pide eliminarla.
class _DetallePrenda extends StatelessWidget {
  const _DetallePrenda({required this.prenda, required this.permiteBorrar});

  final Prenda prenda;
  final bool permiteBorrar;

  @override
  Widget build(BuildContext context) {
    final TextTheme texto = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                MuestraPrenda(prenda: prenda, tamano: 72),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(_tipo(prenda), style: texto.titleLarge),
                      Text(prenda.slot.etiqueta, style: texto.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _Atributo('Color', prenda.categoriaColor.etiqueta),
            if (prenda.texturaCore case final String textura)
              _Atributo('Textura', _etiquetaCore(textura))
            else if (prenda.textura case final Textura textura)
              _Atributo('Textura', textura.etiqueta),
            _Atributo('Patrón', prenda.patron.etiqueta),
            if (prenda.formalidadCore case final String formalidad)
              _Atributo('Formalidad', _etiquetaCore(formalidad))
            else if (prenda.formalidad case final Formalidad formalidad)
              _Atributo('Formalidad', formalidad.etiqueta),
            const SizedBox(height: 8),
            Text('Clima', style: texto.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (final Clima c in prenda.climaApto)
                  Chip(
                    avatar: Icon(c.icono, size: 18),
                    label: Text(c.etiqueta),
                  ),
              ],
            ),
            if (permiteBorrar) const SizedBox(height: 24),
            if (permiteBorrar)
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Eliminar del clóset'),
              ),
          ],
        ),
      ),
    );
  }
}

String _etiquetaCore(String codigo) =>
    '${codigo[0]}${codigo.substring(1).toLowerCase().replaceAll('_', ' ')}';

String _tipo(Prenda prenda) {
  final String? codigo = prenda.tipoCore;
  return codigo == null || codigo == 'CALZADO'
      ? prenda.tipo.etiqueta
      : _etiquetaCore(codigo);
}

class _Atributo extends StatelessWidget {
  const _Atributo(this.nombre, this.valor);

  final String nombre;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(nombre, style: Theme.of(context).textTheme.labelLarge),
          ),
          Expanded(child: Text(valor)),
        ],
      ),
    );
  }
}
