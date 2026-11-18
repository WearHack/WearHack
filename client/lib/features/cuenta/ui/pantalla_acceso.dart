import 'package:flutter/material.dart';
import 'package:wearhack/app/marca.dart';
import 'package:wearhack/core/ui/movimiento.dart';
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
    final ColorScheme colores = Theme.of(context).colorScheme;
    final TextTheme texto = Theme.of(context).textTheme;
    final String titulo = _esperandoCodigo
        ? 'Revisa tu correo'
        : (_creandoCuenta ? 'Crea tu cuenta' : 'Entra a tu cuenta');

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Aparece(child: _Encabezado()),
                  const SizedBox(height: 32),
                  // El formulario entra despues de la marca, y al cambiar
                  // entre entrar y crear cuenta el alto se ajusta con suavidad.
                  Aparece(
                    indice: 3,
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      alignment: Alignment.topCenter,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text(
                            titulo,
                            style: texto.headlineSmall,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          if (_esperandoCodigo)
                            ..._confirmacion()
                          else
                            ..._formulario(),
                          if (_error != null) ...<Widget>[
                            const SizedBox(height: 16),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: colores.errorContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Icon(
                                      Icons.error_outline,
                                      size: 20,
                                      color: colores.onErrorContainer,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _error!,
                                        style: TextStyle(
                                          color: colores.onErrorContainer,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          if (widget.autenticacion.googleDisponible &&
                              !_esperandoCodigo) ...<Widget>[
                            const SizedBox(height: 20),
                            const _Separador(),
                            const SizedBox(height: 20),
                            OutlinedButton(
                              onPressed: _ocupado ? null : _entrarConGoogle,
                              child: const Text('Continuar con Google'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// El texto de un boton, con un indicador pequeno mientras se espera.
  Widget _contenidoBoton(String texto) => Row(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: <Widget>[
      if (_ocupado) ...<Widget>[
        const SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
      ],
      Text(texto),
    ],
  );

  List<Widget> _formulario() => <Widget>[
    TextField(
      controller: _correo,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const <String>[AutofillHints.email],
      decoration: const InputDecoration(labelText: 'Correo'),
    ),
    const SizedBox(height: 12),
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
      child: _contenidoBoton(_creandoCuenta ? 'Crear cuenta' : 'Entrar'),
    ),
    const SizedBox(height: 4),
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
    Text(
      'Te enviamos un codigo a ${_correo.text.trim()}.',
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 16),
    TextField(
      controller: _codigo,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(labelText: 'Codigo'),
    ),
    const SizedBox(height: 24),
    FilledButton(
      onPressed: _ocupado ? null : _confirmar,
      child: _contenidoBoton('Confirmar'),
    ),
  ];
}

/// La marca, el nombre y una linea que dice de que va la app.
class _Encabezado extends StatelessWidget {
  const _Encabezado();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;
    final TextTheme texto = Theme.of(context).textTheme;
    return Column(
      children: <Widget>[
        const MarcaWearHack(alto: 88),
        const SizedBox(height: 16),
        // "Wear" fino y "Hack" grueso, como en el logo.
        Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(
                text: 'Wear',
                style: TextStyle(
                  fontWeight: FontWeight.w300,
                  color: colores.tertiary,
                ),
              ),
              TextSpan(
                text: 'Hack',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: colores.tertiary,
                ),
              ),
            ],
            style: const TextStyle(fontSize: 36, letterSpacing: -0.5),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tu clóset, tus colores.',
          style: texto.bodyLarge?.copyWith(color: colores.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Una linea con una "o" en medio, entre el correo y Google.
class _Separador extends StatelessWidget {
  const _Separador();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('o', style: TextStyle(color: colores.onSurfaceVariant)),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}
