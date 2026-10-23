/// Pantalla 2: las 15 tomas de esta persona con este celular, y su lote.
///
/// 5 luces x 3 repeticiones. Cada casilla es una toma pendiente o hecha. Tocar
/// una pendiente abre la camara; tocar una hecha pregunta si se reemplaza. Abajo
/// estan Exportar (el zip del lote de esta persona, por la hoja de compartir) y
/// Borrar (pide los 8 primeros caracteres del hash que muestra
/// `importar_lote.py` para ese lote).
library;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:wearhack/features/captura_pruebas/lote.dart';
import 'package:wearhack/features/captura_pruebas/modelos.dart';
import 'package:wearhack/features/captura_pruebas/ui/dependencias.dart';
import 'package:wearhack/features/captura_pruebas/ui/pantalla_captura.dart';
import 'package:wearhack/features/captura_pruebas/ui/sesion.dart';

class PantallaCuadriculaCaptura extends StatefulWidget {
  const PantallaCuadriculaCaptura({
    super.key,
    required this.dependencias,
    required this.sesion,
  });

  final DependenciasCaptura dependencias;
  final SesionCaptura sesion;

  @override
  State<PantallaCuadriculaCaptura> createState() =>
      _PantallaCuadriculaCapturaState();
}

class _PantallaCuadriculaCapturaState extends State<PantallaCuadriculaCaptura> {
  /// Nombres base de las tomas ya hechas de ESTA persona con ESTE celular.
  Set<String> _hechas = <String>{};

  /// Las tomas del lote de ESTA persona, con cualquier celular: lo que se
  /// exportaria o borraria.
  int _totalDelLote = 0;

  bool _cargando = true;
  bool _ocupado = false;

  DependenciasCaptura get _d => widget.dependencias;
  SesionCaptura get _s => widget.sesion;

  IdToma _id(Luz luz, Repeticion rep) => IdToma(
    seudonimo: _s.seudonimo,
    luz: luz,
    celular: _s.celular,
    repeticion: rep,
  );

  @override
  void initState() {
    super.initState();
    _recargar();
  }

  Future<void> _recargar() async {
    final List<IdToma> tomas = await _d.almacen.listarTomas(
      persona: _s.seudonimo,
    );
    if (!mounted) return;
    setState(() {
      _totalDelLote = tomas.length;
      _hechas = <String>{
        for (final IdToma t in tomas)
          if (t.celular == _s.celular) t.nombreBase,
      };
      _cargando = false;
    });
  }

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _abrir(Luz luz, Repeticion rep) async {
    final IdToma id = _id(luz, rep);
    final bool yaExiste = _hechas.contains(id.nombreBase);
    if (yaExiste) {
      final bool? reemplazar = await showDialog<bool>(
        context: context,
        builder: (BuildContext c) => AlertDialog(
          key: const Key('dialogo_reemplazo'),
          title: const Text('Reemplazar la toma?'),
          content: Text('Ya existe ${id.nombreBase}. La nueva la reemplaza.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              key: const Key('confirmar_reemplazo'),
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Reemplazar'),
            ),
          ],
        ),
      );
      if (reemplazar != true) return;
    }
    if (!mounted) return;
    final bool? guardada = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PantallaCaptura(
          dependencias: _d,
          sesion: _s,
          id: id,
          reemplazar: yaExiste,
        ),
      ),
    );
    if (guardada == true) await _recargar();
  }

  Future<void> _exportar() async {
    setState(() => _ocupado = true);
    try {
      final ResultadoExportacion r = await exportarLote(
        _d.almacen,
        persona: _s.seudonimo,
      );
      await _d.compartir(r.zip);
      _aviso('Lote exportado: ${p.basename(r.zip.path)}');
    } on LoteVacio {
      _aviso('No hay tomas que exportar');
    } on IntegridadFallida catch (e) {
      _aviso('El lote tiene problemas: ${e.problemas.take(3).join('; ')}');
    } on Object catch (e) {
      _aviso('No se pudo exportar: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _borrar() async {
    final bool? borrado = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) =>
          _DialogoDeBorrado(dependencias: _d, persona: _s.seudonimo),
    );
    if (borrado == true) {
      String texto = 'Lote de ${_s.seudonimo} borrado';
      try {
        await _d.limpiarTemporales();
      } on Object catch (e) {
        texto = '$texto, pero no se pudo quitar la copia temporal del zip: $e';
      }
      _aviso(texto);
      await _recargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final int hechas = _hechas.length;
    return Scaffold(
      appBar: AppBar(title: Text('${_s.seudonimo} - ${_s.celular.codigo}')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '$hechas/15 tomas de esta persona con este celular - '
                    '$_totalDelLote en el lote de ${_s.seudonimo}',
                    key: const Key('resumen'),
                  ),
                ),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 3,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    childAspectRatio: 1.4,
                    // 5 luces x 3 repeticiones, de izquierda a derecha por fila.
                    children: <Widget>[
                      for (final Luz luz in Luz.values)
                        for (final Repeticion rep in Repeticion.values)
                          _Casilla(
                            luz: luz,
                            repeticion: rep,
                            hecha: _hechas.contains(_id(luz, rep).nombreBase),
                            onTap: _ocupado ? null : () => _abrir(luz, rep),
                          ),
                    ],
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton(
                            key: const Key('boton_exportar'),
                            onPressed: _ocupado ? null : _exportar,
                            child: Text('Exportar lote ${_s.seudonimo}'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            key: const Key('boton_borrar'),
                            onPressed: _ocupado ? null : _borrar,
                            child: Text('Borrar lote ${_s.seudonimo}'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Casilla extends StatelessWidget {
  const _Casilla({
    required this.luz,
    required this.repeticion,
    required this.hecha,
    required this.onTap,
  });

  final Luz luz;
  final Repeticion repeticion;
  final bool hecha;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key('celda_${luz.codigo}_${repeticion.codigo}'),
      color: hecha ? Theme.of(context).colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('${luz.codigo} ${repeticion.codigo}'),
              Icon(hecha ? Icons.check_circle : Icons.radio_button_unchecked),
              Text(
                hecha
                    ? 'hecha'
                    : (repeticion.llevaTarjetaGris
                          ? 'con tarjeta'
                          : 'pendiente'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pide los 8 primeros caracteres del hash global y borra el lote de la persona.
///
/// El hash lo muestra `importar_lote.py` en el computador. Se compara contra el
/// del estado actual: si se tomo una foto despues de exportar, el prefijo viejo
/// ya no vale.
class _DialogoDeBorrado extends StatefulWidget {
  const _DialogoDeBorrado({required this.dependencias, required this.persona});

  final DependenciasCaptura dependencias;
  final Seudonimo persona;

  @override
  State<_DialogoDeBorrado> createState() => _DialogoDeBorradoState();
}

class _DialogoDeBorradoState extends State<_DialogoDeBorrado> {
  final TextEditingController _texto = TextEditingController();
  String? _error;
  bool _trabajando = false;

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    setState(() {
      _error = null;
      _trabajando = true;
    });
    try {
      await borrarLote(
        widget.dependencias.almacen,
        persona: widget.persona,
        confirmacion: _texto.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ConfirmacionIncorrecta {
      if (mounted) {
        setState(() {
          _error =
              'No coincide con el hash del lote actual. Si tomaste fotos '
              'despues de exportar, exporta e importa otra vez.';
        });
      }
    } on BorradoIncompleto catch (e) {
      if (mounted) {
        setState(
          () => _error =
              'El borrado no termino: ${e.restantes.length} archivos siguen ahi.',
        );
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'No se pudo borrar: $e');
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('dialogo_borrado'),
      title: Text('Borrar el lote de ${widget.persona}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Borra las tomas y las exportaciones de ${widget.persona} en este '
            'celular; las de las demas personas no se tocan. Antes, importa el '
            'lote en el computador y escribe aqui los 8 primeros caracteres del '
            'hash global que muestra el script.',
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('campo_confirmacion'),
            controller: _texto,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: '8 caracteres del hash',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, key: const Key('error_borrado')),
            ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _trabajando
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('confirmar_borrado'),
          onPressed: _trabajando ? null : _confirmar,
          child: const Text('Borrar'),
        ),
      ],
    );
  }
}
