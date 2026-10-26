/// La entrada a la colorimetria: pedir la autorizacion, ver que se dio y
/// revocarla.
///
/// La colorimetria es opcional (politica, seccion 6): quien la omite no pierde
/// nada del resto de la app, y puede volver aqui cuando quiera.
library;

import 'package:flutter/material.dart';
import 'package:wearhack/core/ui/estados.dart';
import 'package:wearhack/core/ui/formato.dart';
import 'package:wearhack/features/colorimetria/consentimiento.dart';
import 'package:wearhack/features/colorimetria/repositorio_consentimiento.dart';
import 'package:wearhack/features/colorimetria/ui/pantalla_consentimiento.dart';
import 'package:wearhack/features/colorimetria/ui/pantalla_foto_rostro.dart';
import 'package:wearhack/platform/captura/camara.dart';
import 'package:wearhack/platform/captura/contratos.dart';

class PantallaColorimetria extends StatefulWidget {
  const PantallaColorimetria({
    super.key,
    required this.repositorio,
    required this.capturaDisponible,
    this.crearCamara,
    this.recortador,
  });

  final RepositorioConsentimiento repositorio;

  /// Si este target puede tomar la foto del rostro. En web no: no hay ML Kit.
  final bool capturaDisponible;

  /// La camara y el recortador que usa la foto. Si falta alguno, el boton de
  /// tomar la foto queda apagado: asi las pruebas de esta pantalla no
  /// necesitan una camara.
  final CamaraDeCaptura Function()? crearCamara;
  final FaceCropper? recortador;

  @override
  State<PantallaColorimetria> createState() => _PantallaColorimetriaState();
}

class _PantallaColorimetriaState extends State<PantallaColorimetria> {
  late Future<Consentimiento?> _carga = widget.repositorio
      .consentimientoColorimetria();

  void _recargar() {
    setState(() {
      _carga = widget.repositorio.consentimientoColorimetria();
    });
  }

  Future<void> _pedirAutorizacion() async {
    final DecisionConsentimiento? decision = await Navigator.of(context)
        .push<DecisionConsentimiento>(
          MaterialPageRoute<DecisionConsentimiento>(
            builder: (_) => const PantallaConsentimiento(),
          ),
        );
    // Salir con la flecha de atras no es decidir: no se registra nada.
    if (decision == null) return;

    await widget.repositorio.registrar(decision, versionTextoConsentimiento);
    if (!mounted) return;
    _recargar();
  }

  Future<void> _tomarFoto() async {
    final CamaraDeCaptura Function()? crearCamara = widget.crearCamara;
    final FaceCropper? recortador = widget.recortador;
    if (crearCamara == null || recortador == null) return;

    final RecorteFacial? recorte = await Navigator.of(context)
        .push<RecorteFacial>(
          MaterialPageRoute<RecorteFacial>(
            builder: (_) => PantallaFotoRostro(
              repositorio: widget.repositorio,
              crearCamara: crearCamara,
              recortador: recortador,
            ),
          ),
        );
    if (recorte == null || !mounted) return;

    // El envio al servicio de colorimetria se conecta cuando exista el cliente
    // HTTP. Hasta entonces el recorte se descarta aqui: no se guarda.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Foto lista. El análisis se conectará cuando el servicio esté '
          'disponible.',
        ),
      ),
    );
  }

  Future<void> _revocar() async {
    final bool? confirmado = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('¿Revocar la autorización?'),
        content: const Text(
          'Borraremos tus valores de color y tu resultado. Puedes volver a '
          'autorizar cuando quieras.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Revocar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;

    await widget.repositorio.revocar();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Autorización revocada')));
    _recargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tu temporada de color')),
      body: FutureBuilder<Consentimiento?>(
        future: _carga,
        builder:
            (BuildContext context, AsyncSnapshot<Consentimiento?> snapshot) {
              if (snapshot.hasError) {
                return ErrorDeCarga(onReintentar: _recargar);
              }
              if (snapshot.connectionState != ConnectionState.done &&
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final Consentimiento? c = snapshot.data;

              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      if (c != null && c.vigente)
                        _Autorizado(
                          consentimiento: c,
                          capturaDisponible: widget.capturaDisponible,
                          onTomarFoto:
                              widget.crearCamara != null &&
                                  widget.recortador != null
                              ? _tomarFoto
                              : null,
                          onRevocar: _revocar,
                        )
                      else
                        _SinAutorizar(
                          consentimiento: c,
                          onEmpezar: _pedirAutorizacion,
                        ),
                    ],
                  ),
                ),
              );
            },
      ),
    );
  }
}

class _SinAutorizar extends StatelessWidget {
  const _SinAutorizar({required this.consentimiento, required this.onEmpezar});

  /// `null` si nunca decidio o revoco.
  final Consentimiento? consentimiento;
  final VoidCallback onEmpezar;

  @override
  Widget build(BuildContext context) {
    final TextTheme texto = Theme.of(context).textTheme;
    final Consentimiento? c = consentimiento;

    final String? aviso = switch (c) {
      Consentimiento(desactualizado: true) =>
        'El texto de la autorización cambió desde que la diste. Revísalo de '
            'nuevo para continuar.',
      Consentimiento(decision: DecisionConsentimiento.omitio) =>
        'Omitiste este paso. Puedes hacerlo cuando quieras.',
      _ => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Con una foto de tu rostro calculamos tu temporada de color y la '
          'usamos para que tus outfits te favorezcan más.',
          style: texto.bodyLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Es opcional: sin ella la app funciona igual.',
          style: texto.bodyMedium,
        ),
        if (aviso != null) ...<Widget>[
          const SizedBox(height: 16),
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.info_outline),
                  const SizedBox(width: 12),
                  Expanded(child: Text(aviso)),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: onEmpezar,
          child: Text(
            c != null && c.desactualizado
                ? 'Revisar la autorización'
                : 'Calcular mi temporada',
          ),
        ),
      ],
    );
  }
}

class _Autorizado extends StatelessWidget {
  const _Autorizado({
    required this.consentimiento,
    required this.capturaDisponible,
    required this.onTomarFoto,
    required this.onRevocar,
  });

  final Consentimiento consentimiento;
  final bool capturaDisponible;

  /// `null` si no hay camara conectada: el boton queda apagado.
  final VoidCallback? onTomarFoto;
  final VoidCallback onRevocar;

  @override
  Widget build(BuildContext context) {
    final TextTheme texto = Theme.of(context).textTheme;
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.verified_user_outlined, color: colores.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Autorizaste el análisis', style: texto.titleMedium),
                  Text(
                    'El ${formatoFecha(consentimiento.fecha)}.',
                    style: texto.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text('Siguiente paso', style: texto.titleSmall),
        const SizedBox(height: 4),
        if (capturaDisponible) ...<Widget>[
          const Text(
            'Toma una foto de tu rostro con buena luz. Solo el recorte de tu '
            'cara sale del teléfono.',
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onTomarFoto,
            child: Text(
              onTomarFoto == null
                  ? 'Tomar la foto (próximamente)'
                  : 'Tomar la foto',
            ),
          ),
        ] else
          const Text(
            'La foto del rostro se toma desde la app móvil. En la web no hay '
            'cámara.',
          ),
        const SizedBox(height: 32),
        TextButton.icon(
          onPressed: onRevocar,
          icon: const Icon(Icons.block),
          label: const Text('Revocar autorización'),
        ),
      ],
    );
  }
}
