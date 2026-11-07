/// La entrada a la colorimetria: pedir la autorizacion, ver que se dio y
/// revocarla.
///
/// La colorimetria es opcional (politica, seccion 6): quien la omite no pierde
/// nada del resto de la app, y puede volver aqui cuando quiera.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:wearhack/core/ui/estados.dart';
import 'package:wearhack/core/ui/formato.dart';
import 'package:wearhack/features/colorimetria/consentimiento.dart';
import 'package:wearhack/features/colorimetria/perfil_colorimetria.dart';
import 'package:wearhack/features/colorimetria/repositorio_consentimiento.dart';
import 'package:wearhack/features/colorimetria/ui/pantalla_consentimiento.dart';
import 'package:wearhack/features/colorimetria/ui/pantalla_foto_rostro.dart';
import 'package:wearhack/features/cuenta/cliente_usuarios.dart';
import 'package:wearhack/platform/captura/camara.dart';
import 'package:wearhack/platform/captura/contratos.dart';

class PantallaColorimetria extends StatefulWidget {
  const PantallaColorimetria({
    super.key,
    required this.repositorio,
    required this.capturaDisponible,
    this.crearCamara,
    this.recortador,
    this.servicio,
  });

  final RepositorioConsentimiento repositorio;

  /// Donde se manda el recorte y se guarda el resultado. Sin el (no hay cuenta
  /// ni Core), la foto se toma pero no se analiza.
  final ServicioColorimetria? servicio;

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

  PerfilColorimetria? _perfil;
  bool _analizando = false;

  /// Lo que salio mal con el ultimo analisis, para mostrarlo tal cual.
  String? _errorAnalisis;

  /// El recorte que no se pudo analizar porque el servicio no estaba
  /// disponible, para reintentar sin repetir la foto. Solo vive en memoria:
  /// se suelta al analizarse, al salir de la pantalla o si el error no es de
  /// disponibilidad. Nunca se guarda.
  Uint8List? _recortePendiente;

  @override
  void initState() {
    super.initState();
    _cargarPerfil();
  }

  @override
  void dispose() {
    _recortePendiente = null;
    super.dispose();
  }

  Future<void> _cargarPerfil() async {
    final ServicioColorimetria? servicio = widget.servicio;
    if (servicio == null) return;
    try {
      final PerfilColorimetria? perfil = await servicio.perfil();
      if (mounted) setState(() => _perfil = perfil);
    } on Object {
      // Sin resultado guardado o sin red: la pantalla sigue sirviendo para el
      // resto. El resultado se vuelve a pedir al volver a entrar.
    }
  }

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
    await _analizar(recorte.png);
  }

  Future<void> _analizar(Uint8List png) async {
    final ServicioColorimetria? servicio = widget.servicio;
    if (servicio == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Foto lista. Inicia sesión para calcular tu temporada.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _analizando = true;
      _errorAnalisis = null;
    });
    try {
      final PerfilColorimetria perfil = await servicio.analizar(png);
      if (!mounted) return;
      setState(() {
        _perfil = perfil;
        _recortePendiente = null;
      });
    } on ErrorDelCore catch (error) {
      if (!mounted) return;
      setState(() {
        // 422: la foto no sirve (sin rostro, sin piel suficiente) o falta el
        // consentimiento; el mensaje del Core dice cual. Hay que repetirla.
        // 503: el servicio de IA no esta; se puede reintentar con la misma.
        _recortePendiente = error.estado == 503 ? png : null;
        _errorAnalisis = error.estado == 503
            ? 'El análisis no está disponible ahora. Inténtalo de nuevo en '
                  'unos minutos.'
            : error.mensaje;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _recortePendiente = png;
        _errorAnalisis =
            'No pudimos conectar. Revisa tu conexión e inténtalo de nuevo.';
      });
    } finally {
      if (mounted) setState(() => _analizando = false);
    }
  }

  Future<void> _reintentar() async {
    final Uint8List? png = _recortePendiente;
    if (png != null) await _analizar(png);
  }

  Future<void> _borrarResultado() async {
    final bool? confirmado = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('¿Borrar tu resultado?'),
        content: const Text(
          'Borraremos tu temporada y tus valores de color. Tu autorización '
          'sigue vigente y puedes calcularla de nuevo.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;
    await widget.servicio?.borrarPerfil();
    if (!mounted) return;
    setState(() => _perfil = null);
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
    // Revocar borra tambien el resultado en el Core.
    setState(() {
      _perfil = null;
      _recortePendiente = null;
      _errorAnalisis = null;
    });
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
                                  widget.recortador != null &&
                                  !_analizando
                              ? _tomarFoto
                              : null,
                          onRevocar: _revocar,
                          perfil: _perfil,
                          analizando: _analizando,
                          error: _errorAnalisis,
                          onReintentar: _recortePendiente == null
                              ? null
                              : _reintentar,
                          onBorrarResultado: _borrarResultado,
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
    required this.perfil,
    required this.analizando,
    required this.error,
    required this.onReintentar,
    required this.onBorrarResultado,
  });

  final Consentimiento consentimiento;
  final bool capturaDisponible;

  /// `null` si no hay camara conectada: el boton queda apagado.
  final VoidCallback? onTomarFoto;
  final VoidCallback onRevocar;

  final PerfilColorimetria? perfil;
  final bool analizando;
  final String? error;

  /// `null` si no hay un recorte en memoria para reintentar.
  final VoidCallback? onReintentar;
  final VoidCallback onBorrarResultado;

  @override
  Widget build(BuildContext context) {
    final TextTheme texto = Theme.of(context).textTheme;
    final ColorScheme colores = Theme.of(context).colorScheme;
    final PerfilColorimetria? p = perfil;

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
        if (p != null) ...<Widget>[
          const SizedBox(height: 24),
          _TarjetaPerfil(perfil: p, onBorrar: onBorrarResultado),
        ],
        if (analizando) ...<Widget>[
          const SizedBox(height: 24),
          const Row(
            children: <Widget>[
              SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Expanded(child: Text('Calculando tu temporada…')),
            ],
          ),
        ],
        if (error != null) ...<Widget>[
          const SizedBox(height: 24),
          Card(
            color: colores.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    error!,
                    style: TextStyle(color: colores.onErrorContainer),
                  ),
                  if (onReintentar != null)
                    TextButton(
                      onPressed: analizando ? null : onReintentar,
                      child: const Text('Reintentar'),
                    ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Text(
          p == null ? 'Siguiente paso' : 'Otra foto',
          style: texto.titleSmall,
        ),
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

/// El resultado de la colorimetria: la temporada y cuanta confianza tiene el
/// servicio en ella.
class _TarjetaPerfil extends StatelessWidget {
  const _TarjetaPerfil({required this.perfil, required this.onBorrar});

  final PerfilColorimetria perfil;
  final VoidCallback onBorrar;

  /// `primavera_clara` se muestra como "Primavera clara".
  static String _legible(String texto) {
    final String t = texto.replaceAll('_', ' ').trim();
    return t.isEmpty ? t : '${t[0].toUpperCase()}${t.substring(1)}';
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme texto = Theme.of(context).textTheme;
    final String? temporada = perfil.temporada;
    final double? confianza = perfil.confianza;
    final DateTime? fecha = perfil.calculadoEn;
    return Card(
      key: const Key('perfil_colorimetria'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Tu temporada', style: texto.labelLarge),
            const SizedBox(height: 4),
            Text(
              temporada == null ? 'Sin clasificar' : _legible(temporada),
              style: texto.headlineSmall,
            ),
            if (confianza != null)
              Text('Confianza: ${(confianza * 100).round()} %'),
            if (temporada == null)
              const Text(
                'La foto no alcanzó para decidir. Prueba con más luz y sin '
                'sombras en el rostro.',
              ),
            if (perfil.ejes.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: <Widget>[
                  for (final String e in perfil.ejes)
                    Chip(label: Text(_legible(e))),
                ],
              ),
            ],
            if (fecha != null) Text('Calculada el ${formatoFecha(fecha)}.'),
            TextButton.icon(
              onPressed: onBorrar,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Borrar mi resultado'),
            ),
          ],
        ),
      ),
    );
  }
}
