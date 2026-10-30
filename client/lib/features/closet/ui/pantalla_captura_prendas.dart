/// Fotografiar prendas una tras otra (issue #11).
///
/// Disparar solo encola la foto y vuelve: el procesamiento y la subida corren en
/// la cola, en segundo plano, y siguen al salir de esta pantalla. Aqui se ve en
/// que punto va cada foto y se decide que hacer con las fallidas.
///
/// La revision de cada prenda (correcciones y preguntas de textura) es otra
/// pantalla, al final de la sesion: issue #55.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wearhack/features/closet/captura/cola_captura.dart';
import 'package:wearhack/features/closet/captura/item_cola.dart';
import 'package:wearhack/platform/captura/camara.dart';

class PantallaCapturaPrendas extends StatefulWidget {
  const PantallaCapturaPrendas({
    super.key,
    required this.cola,
    required this.crearCamara,
    required this.termico,
    this.intervaloTermico = const Duration(seconds: 2),
  });

  /// La cola de la app. No es de esta pantalla: no se detiene al salir.
  final ColaCaptura cola;
  final CamaraDeCaptura Function() crearCamara;

  /// El mismo estado termico que usa la cola, para avisar de la pausa.
  final EstadoTermico termico;

  /// Cada cuanto se mira la temperatura para el aviso.
  final Duration intervaloTermico;

  @override
  State<PantallaCapturaPrendas> createState() => _PantallaCapturaPrendasState();
}

class _PantallaCapturaPrendasState extends State<PantallaCapturaPrendas> {
  late final CamaraDeCaptura _camara = widget.crearCamara();
  late final Future<void> _apertura = _camara.inicializar();
  late List<ItemCola> _items = widget.cola.items;
  late bool _caliente = widget.termico.caliente;
  StreamSubscription<List<ItemCola>>? _cambios;
  Timer? _vigilanciaTermica;
  bool _disparando = false;

  @override
  void initState() {
    super.initState();
    _cambios = widget.cola.cambios.listen(
      (List<ItemCola> items) => setState(() => _items = items),
    );
    _vigilanciaTermica = Timer.periodic(widget.intervaloTermico, (_) {
      final bool caliente = widget.termico.caliente;
      if (caliente != _caliente) setState(() => _caliente = caliente);
    });
    // Lo que quedo de otra sesion sigue su camino.
    widget.cola.arrancar();
  }

  @override
  void dispose() {
    _cambios?.cancel();
    _vigilanciaTermica?.cancel();
    unawaited(_camara.liberar());
    super.dispose();
  }

  int _contar(EstadoItem estado) =>
      _items.where((ItemCola i) => i.estado == estado).length;

  void _avisar(String mensaje) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _disparar() async {
    if (_disparando) return;
    setState(() => _disparando = true);
    try {
      final FotoTomada foto = await _camara.tomarFoto();
      await widget.cola.encolar(foto.bytes);
    } on ColaLlena catch (e) {
      _avisar(
        'Hay ${e.tope} fotos esperando. Espera a que se procesen para seguir.',
      );
    } on Object {
      _avisar('No se pudo tomar la foto. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _disparando = false);
    }
  }

  Future<void> _abrirFallidas() => showModalBottomSheet<void>(
    context: context,
    builder: (BuildContext context) => _HojaFallidas(cola: widget.cola),
  );

  @override
  Widget build(BuildContext context) {
    final int fallidas = _contar(EstadoItem.fallida);
    return Scaffold(
      appBar: AppBar(title: const Text('Agregar prendas')),
      body: Column(
        children: <Widget>[
          _Resumen(
            porProcesar: _contar(EstadoItem.porProcesar),
            porSubir: _contar(EstadoItem.porSubir),
            fallidas: fallidas,
            alVerFallidas: fallidas > 0 ? _abrirFallidas : null,
          ),
          if (_caliente)
            const MaterialBanner(
              key: Key('aviso_calor'),
              leading: Icon(Icons.thermostat),
              content: Text(
                'El teléfono está caliente: el procesamiento queda en pausa. '
                'Puedes seguir tomando fotos.',
              ),
              actions: <Widget>[SizedBox.shrink()],
            ),
          Expanded(
            child: FutureBuilder<void>(
              future: _apertura,
              builder: (BuildContext context, AsyncSnapshot<void> estado) {
                if (estado.hasError) {
                  return _ErrorCamara(error: estado.error!);
                }
                if (estado.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                return Center(child: _camara.vistaPrevia());
              },
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FutureBuilder<void>(
        future: _apertura,
        builder: (BuildContext context, AsyncSnapshot<void> estado) {
          final bool lista =
              estado.connectionState == ConnectionState.done &&
              !estado.hasError;
          return FloatingActionButton.large(
            key: const Key('disparar'),
            tooltip: 'Tomar foto',
            onPressed: lista && !_disparando ? _disparar : null,
            child: const Icon(Icons.camera_alt),
          );
        },
      ),
    );
  }
}

class _Resumen extends StatelessWidget {
  const _Resumen({
    required this.porProcesar,
    required this.porSubir,
    required this.fallidas,
    required this.alVerFallidas,
  });

  final int porProcesar;
  final int porSubir;
  final int fallidas;
  final VoidCallback? alVerFallidas;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(8),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: <Widget>[
        Chip(
          key: const Key('por_procesar'),
          avatar: const Icon(Icons.hourglass_empty, size: 18),
          label: Text('Por procesar: $porProcesar'),
        ),
        Chip(
          key: const Key('por_subir'),
          avatar: const Icon(Icons.cloud_upload_outlined, size: 18),
          label: Text('Por subir: $porSubir'),
        ),
        ActionChip(
          key: const Key('fallidas'),
          avatar: const Icon(Icons.error_outline, size: 18),
          label: Text('Fallidas: $fallidas'),
          onPressed: alVerFallidas,
        ),
      ],
    ),
  );
}

class _ErrorCamara extends StatelessWidget {
  const _ErrorCamara({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        error is SinCamaraTrasera
            ? 'Este teléfono no tiene cámara trasera.'
            : 'No se pudo abrir la cámara. Revisa el permiso en los ajustes '
                  'del teléfono.',
        textAlign: TextAlign.center,
      ),
    ),
  );
}

/// Las fotos que agotaron sus intentos. La original sigue guardada: se puede
/// reintentar o descartar.
class _HojaFallidas extends StatefulWidget {
  const _HojaFallidas({required this.cola});

  final ColaCaptura cola;

  @override
  State<_HojaFallidas> createState() => _HojaFallidasState();
}

class _HojaFallidasState extends State<_HojaFallidas> {
  List<ItemCola> get _fallidas => widget.cola.items
      .where((ItemCola i) => i.estado == EstadoItem.fallida)
      .toList();

  Future<void> _reintentar() async {
    await widget.cola.reintentarFallidas();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _descartar(String id) async {
    await widget.cola.descartar(id);
    if (!mounted) return;
    if (_fallidas.isEmpty) {
      Navigator.of(context).pop();
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<ItemCola> fallidas = _fallidas;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            title: Text('${fallidas.length} fotos no se pudieron procesar'),
            trailing: FilledButton(
              key: const Key('reintentar_fallidas'),
              onPressed: _reintentar,
              child: const Text('Reintentar todas'),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: <Widget>[
                for (final ItemCola item in fallidas)
                  ListTile(
                    leading: const Icon(Icons.broken_image_outlined),
                    title: Text('Intentos: ${item.intentos}'),
                    subtitle: item.ultimoError == null
                        ? null
                        : Text(
                            item.ultimoError!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                    trailing: IconButton(
                      key: Key('descartar_${item.id}'),
                      tooltip: 'Descartar',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _descartar(item.id),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
