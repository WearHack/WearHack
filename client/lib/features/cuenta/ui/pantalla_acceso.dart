import 'package:flutter/material.dart';
import 'package:wearhack/features/cuenta/autenticacion.dart';

/// Entrar o crear cuenta con correo, o entrar con Google.
///
/// Con Google no hay "crear cuenta": la primera entrada la crea en Cognito. La
/// declaracion de mayoria de edad viene despues, en
/// `PantallaCompletarRegistro`, para los dos caminos por igual.
class PantallaAcceso extends StatefulWidget {
  const PantallaAcceso({
    super.key,
    required this.autenticacion,
    required this.alEntrar,
  });

  final Autenticacion autenticacion;
  final VoidCallback alEntrar;

  @override
  State<PantallaAcceso> createState() => _PantallaAccesoState();
}

class _PantallaAccesoState extends State<PantallaAcceso> {
  final TextEditingController _correo = TextEditingController();
  final TextEditingController _clave = TextEditingController();
  final TextEditingController _codigo = TextEditingController();

  bool _creandoCuenta = false;
  bool _esperandoCodigo = false;
  bool _ocupado = false;
  String? _error;

  @override
  void dispose() {
    _correo.dispose();
    _clave.dispose();
    _codigo.dispose();
    super.dispose();
  }

  Future<void> _ejecutar(Future<void> Function() accion) async {
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      await accion();
    } on ErrorDeAutenticacion catch (error) {
      if (mounted) {
        setState(() => _error = error.mensaje);
      }
    } finally {
      if (mounted) {
        setState(() => _ocupado = false);
      }
    }
  }

  Future<void> _entrar() => _ejecutar(() async {
    await widget.autenticacion.iniciarSesion(_correo.text.trim(), _clave.text);
    widget.alEntrar();
  });

  Future<void> _crearCuenta() => _ejecutar(() async {
    await widget.autenticacion.registrarse(_correo.text.trim(), _clave.text);
    setState(() => _esperandoCodigo = true);
  });

  Future<void> _confirmar() => _ejecutar(() async {
    final String correo = _correo.text.trim();
    await widget.autenticacion.confirmarRegistro(correo, _codigo.text.trim());
    await widget.autenticacion.iniciarSesion(correo, _clave.text);
    widget.alEntrar();
  });

  Future<void> _entrarConGoogle() => _ejecutar(() async {
    await widget.autenticacion.iniciarConGoogle();
    widget.alEntrar();
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WearHack')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          if (_esperandoCodigo) ..._confirmacion() else ..._formulario(),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (widget.autenticacion.googleDisponible &&
              !_esperandoCodigo) ...<Widget>[
            const SizedBox(height: 32),
            OutlinedButton(
              onPressed: _ocupado ? null : _entrarConGoogle,
              child: const Text('Continuar con Google'),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _formulario() => <Widget>[
    TextField(
      controller: _correo,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const <String>[AutofillHints.email],
      decoration: const InputDecoration(labelText: 'Correo'),
    ),
    TextField(
      controller: _clave,
      obscureText: true,
      decoration: InputDecoration(
        labelText: 'Contrasena',
        helperText: _creandoCuenta
            ? 'Minimo 8 caracteres, con mayuscula, minuscula y numero'
            : null,
      ),
    ),
    const SizedBox(height: 24),
    FilledButton(
      onPressed: _ocupado ? null : (_creandoCuenta ? _crearCuenta : _entrar),
      child: Text(_creandoCuenta ? 'Crear cuenta' : 'Entrar'),
    ),
    TextButton(
      onPressed: _ocupado
          ? null
          : () => setState(() {
              _creandoCuenta = !_creandoCuenta;
              _error = null;
            }),
      child: Text(
        _creandoCuenta ? 'Ya tengo cuenta' : 'No tengo cuenta: crear una',
      ),
    ),
  ];

  List<Widget> _confirmacion() => <Widget>[
    Text('Te enviamos un codigo a ${_correo.text.trim()}.'),
    TextField(
      controller: _codigo,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(labelText: 'Codigo'),
    ),
    const SizedBox(height: 24),
    FilledButton(
      onPressed: _ocupado ? null : _confirmar,
      child: const Text('Confirmar'),
    ),
  ];
}
