/// Pantalla 1: quien, con que celular, y la autorizacion firmada.
///
/// Si vienes de React: un `StatefulWidget` es un componente con estado. El
/// estado vive en la clase `_PantallaInicioCapturaState` (los campos que
/// empiezan con `_`), y `setState(() { ... })` es el equivalente de `setX(...)`:
/// cambia el valor y vuelve a ejecutar `build`.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:wearhack/features/captura_pruebas/modelos.dart';
import 'package:wearhack/features/captura_pruebas/ui/dependencias.dart';
import 'package:wearhack/features/captura_pruebas/ui/pantalla_cuadricula.dart';
import 'package:wearhack/features/captura_pruebas/ui/sesion.dart';

class PantallaInicioCaptura extends StatefulWidget {
  const PantallaInicioCaptura({super.key, required this.dependencias});

  final DependenciasCaptura dependencias;

  @override
  State<PantallaInicioCaptura> createState() => _PantallaInicioCapturaState();
}

class _PantallaInicioCapturaState extends State<PantallaInicioCaptura> {
  // Empiezan sin elegir a proposito: asi hay que decidir quien es y con que
  // celular, y no se captura a la persona equivocada por dejar un valor puesto.
  String? _seudonimo;
  CodigoCelular? _celular;
  bool _autorizacion = false;
  bool _trueTone = false;

  late final Future<InfoDelDispositivo> _info = widget.dependencias.dispositivo
      .leer();

  @override
  void initState() {
    super.initState();
    // Al abrir el modo se revisa si un cierre a medias dejo tomas incompletas.
    WidgetsBinding.instance.addPostFrameCallback((_) => _revisarIncompletas());
  }

  /// Una toma incompleta es la foto o el recorte sin su `.json` (o un `.tmp`):
  /// lo que deja un cierre a medias. No cuenta como toma y bloquea Exportar, asi
  /// que se ofrece borrarla. Nada se borra sin que la persona lo confirme.
  Future<void> _revisarIncompletas() async {
    final List<File> sobrantes;
    try {
      sobrantes = await widget.dependencias.almacen.archivosIncompletos();
    } on Object catch (e) {
      _aviso('No se pudo revisar si hay tomas incompletas: $e');
      return;
    }
    if (!mounted || sobrantes.isEmpty) return;

    final List<String> nombres = <String>[
      for (final File f in sobrantes) p.basename(f.path),
    ];
    final bool? borrar = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        key: const Key('dialogo_incompletas'),
        title: const Text('Tomas incompletas'),
        content: Text(
          'Un cierre a medias dejo ${nombres.length} archivos sueltos, sin su '
          'toma completa: ${nombres.take(5).join(', ')}'
          '${nombres.length > 5 ? ', ...' : ''}. No cuentan como toma y '
          'impiden exportar el lote. Borrarlos? Despues repite esas tomas.',
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('conservar_incompletas'),
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Conservar'),
          ),
          FilledButton(
            key: const Key('confirmar_borrar_incompletas'),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (borrar != true) return;
    try {
      final int n = await widget.dependencias.almacen.borrarIncompletos();
      _aviso('Borrados $n archivos de tomas incompletas');
    } on Object catch (e) {
      _aviso('No se pudo borrar: $e');
    }
  }

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  /// "Continuar" solo se habilita con las tres cosas. Sin la autorizacion
  /// firmada la captura queda deshabilitada (spec, 3.1).
  bool get _listo => _seudonimo != null && _celular != null && _autorizacion;

  void _continuar() {
    final SesionCaptura sesion = SesionCaptura(
      seudonimo: Seudonimo(_seudonimo!),
      celular: _celular!,
      autorizacionFirmada: _autorizacion,
      trueToneONightShift: _trueTone,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PantallaCuadriculaCaptura(
          dependencias: widget.dependencias,
          sesion: sesion,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Captura de pruebas')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text(
            'Herramienta interna para calibrar la colorimetria. Las fotos se '
            'guardan solo en este celular, sin red, y salen unicamente al '
            'exportar el lote.',
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: const Key('campo_seudonimo'),
            decoration: const InputDecoration(labelText: 'Persona'),
            initialValue: _seudonimo,
            items: <DropdownMenuItem<String>>[
              for (int i = 1; i <= 6; i++)
                DropdownMenuItem<String>(value: 'P$i', child: Text('P$i')),
            ],
            onChanged: (String? v) => setState(() => _seudonimo = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<CodigoCelular>(
            key: const Key('campo_celular'),
            decoration: const InputDecoration(labelText: 'Celular'),
            initialValue: _celular,
            items: <DropdownMenuItem<CodigoCelular>>[
              for (final CodigoCelular c in CodigoCelular.values)
                DropdownMenuItem<CodigoCelular>(
                  value: c,
                  child: Text('${c.codigo} - ${c.descripcion}'),
                ),
            ],
            onChanged: (CodigoCelular? v) => setState(() => _celular = v),
          ),
          if (_celular == CodigoCelular.d3)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'D3 esta reservado para la validacion final: no se usa para '
                'desarrollar la tecnica.',
                key: Key('aviso_d3'),
              ),
            ),
          const SizedBox(height: 12),
          FutureBuilder<InfoDelDispositivo>(
            future: _info,
            builder:
                (BuildContext context, AsyncSnapshot<InfoDelDispositivo> s) {
                  if (s.hasError) {
                    return const Text('No se pudo leer el modelo del celular');
                  }
                  final InfoDelDispositivo? i = s.data;
                  if (i == null) {
                    return const Text('Leyendo el modelo del celular...');
                  }
                  return Text(
                    '${i.modelo} - ${i.sistema} - app ${i.buildApp}',
                    key: const Key('info_dispositivo'),
                  );
                },
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            key: const Key('casilla_autorizacion'),
            title: const Text('Autorizacion de calibracion firmada'),
            subtitle: const Text('Sin ella, la captura queda deshabilitada.'),
            value: _autorizacion,
            onChanged: (bool? v) => setState(() => _autorizacion = v ?? false),
          ),
          CheckboxListTile(
            key: const Key('casilla_true_tone'),
            title: const Text('True Tone o Night Shift activos'),
            subtitle: const Text('iOS no deja leerlos: marcalo a mano.'),
            value: _trueTone,
            onChanged: (bool? v) => setState(() => _trueTone = v ?? false),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('boton_continuar'),
            // `null` en onPressed deshabilita el boton.
            onPressed: _listo ? _continuar : null,
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
  }
}
