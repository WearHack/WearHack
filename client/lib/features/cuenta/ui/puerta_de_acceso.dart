import 'package:flutter/material.dart';
import 'package:wearhack/features/cuenta/autenticacion.dart';
import 'package:wearhack/features/cuenta/cliente_usuarios.dart';
import 'package:wearhack/features/cuenta/ui/pantalla_acceso.dart';
import 'package:wearhack/features/cuenta/ui/pantalla_completar_registro.dart';

/// Decide que se ve: acceso, completar registro o la app.
///
/// El registro tiene dos mitades. La cuenta vive en Cognito y el perfil en el
/// Core. Una cuenta de Cognito sin perfil (la app se cerro a mitad, o es la
/// primera entrada con Google) vuelve a la declaracion de mayoria de edad.
class PuertaDeAcceso extends StatefulWidget {
  const PuertaDeAcceso({
    super.key,
    required this.autenticacion,
    required this.usuarios,
    required this.app,
  });

  final Autenticacion autenticacion;
  final ClienteUsuarios usuarios;
  final Widget app;

  @override
  State<PuertaDeAcceso> createState() => _PuertaDeAccesoState();
}

enum _Paso { cargando, acceso, completarRegistro, listo, error }

class _PuertaDeAccesoState extends State<PuertaDeAcceso> {
  _Paso _paso = _Paso.cargando;
  String? _error;

  @override
  void initState() {
    super.initState();
    _revisar();
  }

  Future<void> _revisar() async {
    setState(() => _paso = _Paso.cargando);
    try {
      if (!await widget.autenticacion.haySesion()) {
        _ir(_Paso.acceso);
        return;
      }
      final PerfilUsuario? perfil = await widget.usuarios.perfil();
      _ir(perfil == null ? _Paso.completarRegistro : _Paso.listo);
    } catch (error) {
      _error = error.toString();
      _ir(_Paso.error);
    }
  }

  void _ir(_Paso paso) {
    if (mounted) {
      setState(() => _paso = paso);
    }
  }

  Future<void> _salir() async {
    await widget.autenticacion.cerrarSesion();
    _ir(_Paso.acceso);
  }

  @override
  Widget build(BuildContext context) {
    switch (_paso) {
      case _Paso.cargando:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case _Paso.acceso:
        return PantallaAcceso(
          autenticacion: widget.autenticacion,
          alEntrar: _revisar,
        );
      case _Paso.completarRegistro:
        return PantallaCompletarRegistro(
          alCompletar: (String? nombre) async {
            await widget.usuarios.completarRegistro(
              nombre: nombre,
              mayorDeEdad: true,
            );
            _ir(_Paso.listo);
          },
          alCancelar: _salir,
        );
      case _Paso.listo:
        return widget.app;
      case _Paso.error:
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(_error ?? 'Error'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _revisar,
                  child: const Text('Reintentar'),
                ),
                TextButton(onPressed: _salir, child: const Text('Salir')),
              ],
            ),
          ),
        );
    }
  }
}
