import 'package:flutter/material.dart';

/// Ultimo paso del registro, igual para correo y para Google: la declaracion de
/// mayoria de edad. El MVP es solo para mayores de 18 (politica de datos,
/// seccion 9). Es una declaracion, no una verificacion.
///
/// La fecha que se muestra es informativa: la que vale la fija el Core al
/// recibirla.
class PantallaCompletarRegistro extends StatefulWidget {
  const PantallaCompletarRegistro({
    super.key,
    required this.alCompletar,
    required this.alCancelar,
    this.hoy,
  });

  /// Recibe el nombre (o null) y crea el perfil en el Core.
  final Future<void> Function(String? nombre) alCompletar;

  /// Cierra la sesion: sin declaracion no hay perfil.
  final VoidCallback alCancelar;

  /// Solo para pruebas.
  final DateTime? hoy;

  @override
  State<PantallaCompletarRegistro> createState() =>
      _PantallaCompletarRegistroState();
}

class _PantallaCompletarRegistroState extends State<PantallaCompletarRegistro> {
  final TextEditingController _nombre = TextEditingController();
  bool _mayorDeEdad = false;
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  Future<void> _completar() async {
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final String nombre = _nombre.text.trim();
      await widget.alCompletar(nombre.isEmpty ? null : nombre);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _enviando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final DateTime hoy = widget.hoy ?? DateTime.now();
    final String fecha =
        '${hoy.year}-${hoy.month.toString().padLeft(2, '0')}-'
        '${hoy.day.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(title: const Text('Completa tu registro')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          TextField(
            controller: _nombre,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Como quieres que te llamemos (opcional)',
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            key: const Key('casilla-mayoria-edad'),
            value: _mayorDeEdad,
            onChanged: _enviando
                ? null
                : (bool? valor) =>
                      setState(() => _mayorDeEdad = valor ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Declaro que soy mayor de 18 anos'),
            subtitle: Text('Fecha de la declaracion: $fecha'),
          ),
          const SizedBox(height: 8),
          const Text(
            'WearHack es solo para mayores de edad. Si no lo eres, no '
            'continues.',
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _mayorDeEdad && !_enviando ? _completar : null,
            child: const Text('Continuar'),
          ),
          TextButton(
            onPressed: _enviando ? null : widget.alCancelar,
            child: const Text('Salir'),
          ),
        ],
      ),
    );
  }
}
