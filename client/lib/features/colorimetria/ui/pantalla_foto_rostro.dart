/// La foto del rostro para la colorimetria (issue #14).
///
/// Lo que esta pantalla garantiza, y por que:
///
/// - **No abre la camara sin consentimiento vigente.** Lo comprueba ella misma
///   antes de crear la camara: no depende de que la pantalla anterior haya
///   escondido el boton. Si el texto de la autorizacion cambio, tambien se
///   niega (politica de datos, seccion 5).
/// - **La foto completa no va a ningun sitio salvo al recortador.** Los bytes de
///   [FotoTomada] viven en una variable local de [_tomar] y no se guardan, no se
///   muestran y no hay un camino de reserva que los envie si el recorte falla
///   (ADR 0016). Sin rostro, se pide repetir.
/// - **El recorte nunca se persiste.** Vive en memoria mientras se revisa y se
///   entrega con `Navigator.pop`; nada se escribe a disco ni a la galeria. Los
///   temporales del plugin de camara y del detector los borran sus
///   implementaciones (`CamaraDeCaptura.tomarFoto` y `DetectorRostroMlKit`).
///
/// Devuelve el [RecorteFacial] si la persona lo acepta, o `null` si sale sin
/// aceptar. El envio al backend no esta aqui: todavia no hay cliente HTTP.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wearhack/core/color/perfil_icc.dart';
import 'package:wearhack/core/recorte/configuracion_recorte.dart';
import 'package:wearhack/features/colorimetria/consentimiento.dart';
import 'package:wearhack/features/colorimetria/repositorio_consentimiento.dart';
import 'package:wearhack/platform/captura/camara.dart';
import 'package:wearhack/platform/captura/contratos.dart';

enum _Fase {
  verificando,
  sinConsentimiento,
  abriendoCamara,
  lista,
  procesando,
  revision,
  sinRostro,
  error,
}

class PantallaFotoRostro extends StatefulWidget {
  const PantallaFotoRostro({
    super.key,
    required this.repositorio,
    required this.crearCamara,
    required this.recortador,
  });

  final RepositorioConsentimiento repositorio;

  /// Se llama **solo despues** de comprobar el consentimiento.
  final CamaraDeCaptura Function() crearCamara;

  final FaceCropper recortador;

  @override
  State<PantallaFotoRostro> createState() => _PantallaFotoRostroState();
}

class _PantallaFotoRostroState extends State<PantallaFotoRostro> {
  _Fase _fase = _Fase.verificando;
  CamaraDeCaptura? _camara;
  bool _camaraLiberada = false;
  RecorteFacial? _recorte;
  String _mensajeError = '';

  @override
  void initState() {
    super.initState();
    unawaited(_arrancar());
  }

  @override
  void dispose() {
    // El recorte se suelta con la pantalla: no se guarda en ningun sitio.
    _recorte = null;
    unawaited(_liberarCamara());
    super.dispose();
  }

  /// Idempotente: se puede llamar desde `dispose` y desde un arranque que
  /// termina despues de que la pantalla ya se cerro.
  Future<void> _liberarCamara() async {
    final CamaraDeCaptura? camara = _camara;
    if (camara == null || _camaraLiberada) return;
    _camaraLiberada = true;
    try {
      await camara.liberar();
    } on Object {
      // Se esta cerrando de todos modos.
    }
  }

  Future<void> _arrancar() async {
    final Consentimiento? consentimiento;
    try {
      consentimiento = await widget.repositorio.consentimientoColorimetria();
    } on Object {
      _fallar('No pudimos comprobar tu autorización. Intenta de nuevo.');
      return;
    }
    if (!mounted) return;
    if (consentimiento == null || !consentimiento.vigente) {
      setState(() => _fase = _Fase.sinConsentimiento);
      return;
    }

    setState(() => _fase = _Fase.abriendoCamara);
    final CamaraDeCaptura camara = widget.crearCamara();
    _camara = camara;
    try {
      await camara.inicializar();
    } on SinCamaraFrontal {
      await _liberarCamara();
      _fallar('Este teléfono no tiene cámara frontal.');
      return;
    } on Object {
      await _liberarCamara();
      _fallar(
        'No pudimos abrir la cámara. Revisa que WearHack tenga permiso para '
        'usarla.',
      );
      return;
    }
    if (!mounted) {
      await _liberarCamara();
      return;
    }
    setState(() => _fase = _Fase.lista);
  }

  void _fallar(String mensaje) {
    if (!mounted) return;
    setState(() {
      _mensajeError = mensaje;
      _fase = _Fase.error;
    });
  }

  Future<void> _tomar() async {
    final CamaraDeCaptura? camara = _camara;
    if (camara == null || _fase != _Fase.lista) return;
    setState(() => _fase = _Fase.procesando);

    try {
      // La foto completa solo existe dentro de este bloque.
      final FotoTomada foto = await camara.tomarFoto();
      final RecorteFacial? recorte = await widget.recortador.recortar(
        foto.bytes,
      );
      if (!mounted) return;
      if (recorte == null) {
        setState(() => _fase = _Fase.sinRostro);
        return;
      }
      setState(() {
        _recorte = recorte;
        _fase = _Fase.revision;
      });
    } on ConfiguracionRecorteInvalida {
      // Faltan los margenes del recorte (`--dart-define`). Es un problema de
      // la build, no de la persona: no se le pide repetir.
      _fallar(
        'Esta versión de la app no tiene configurado el recorte del rostro.',
      );
    } on PerfilIccNoSoportado {
      _fallar(
        'No pudimos leer el color de esa foto. Intenta de nuevo, y si sigue '
        'igual cuéntanos.',
      );
    } on FormatException {
      _fallar(
        'La cámara entregó una foto que no pudimos leer. Repite la foto.',
      );
    } on Object {
      _fallar('No pudimos procesar la foto. Intenta de nuevo.');
    }
  }

  void _repetir() {
    setState(() {
      _recorte = null;
      _fase = _Fase.lista;
    });
  }

  void _usar() {
    final RecorteFacial? recorte = _recorte;
    if (recorte == null) return;
    Navigator.of(context).pop(recorte);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Foto de tu rostro')),
      body: SafeArea(child: _cuerpo(context)),
    );
  }

  Widget _cuerpo(BuildContext context) {
    switch (_fase) {
      case _Fase.verificando:
      case _Fase.abriendoCamara:
        return const Center(child: CircularProgressIndicator());
      case _Fase.sinConsentimiento:
        return _Aviso(
          icono: Icons.lock_outline,
          titulo: 'Falta tu autorización',
          texto:
              'Para tomar la foto necesitamos que autorices el análisis de '
              'color. Vuelve atrás y revisa la autorización.',
          accion: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Volver'),
          ),
        );
      case _Fase.error:
        return _Aviso(
          icono: Icons.error_outline,
          titulo: 'Algo salió mal',
          texto: _mensajeError,
          accion: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Volver'),
          ),
        );
      case _Fase.sinRostro:
        return _Aviso(
          icono: Icons.face_retouching_off,
          titulo: 'No vimos tu rostro',
          texto:
              'Ponlo de frente, con buena luz y sin nada que lo tape, y '
              'repite la foto.',
          accion: FilledButton(
            onPressed: _repetir,
            child: const Text('Repetir'),
          ),
        );
      case _Fase.lista:
      case _Fase.procesando:
        return _Vista(
          camara: _camara!,
          procesando: _fase == _Fase.procesando,
          onTomar: _tomar,
        );
      case _Fase.revision:
        return _Revision(
          recorte: _recorte!,
          onRepetir: _repetir,
          onUsar: _usar,
        );
    }
  }
}

class _Vista extends StatelessWidget {
  const _Vista({
    required this.camara,
    required this.procesando,
    required this.onTomar,
  });

  final CamaraDeCaptura camara;
  final bool procesando;
  final VoidCallback onTomar;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: camara.vistaPrevia(),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Mira de frente, con luz natural si puedes. Solo el recorte de tu '
            'cara sale del teléfono.',
            textAlign: TextAlign.center,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: procesando ? null : onTomar,
            icon: procesando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.camera_alt_outlined),
            label: Text(procesando ? 'Procesando…' : 'Tomar foto'),
          ),
        ),
      ],
    );
  }
}

class _Revision extends StatelessWidget {
  const _Revision({
    required this.recorte,
    required this.onRepetir,
    required this.onUsar,
  });

  final RecorteFacial recorte;
  final VoidCallback onRepetir;
  final VoidCallback onUsar;

  @override
  Widget build(BuildContext context) {
    final TextTheme texto = Theme.of(context).textTheme;
    final List<String> recomendaciones = recorte.controles.recomendaciones;

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Text('Así se verá tu recorte', style: texto.titleMedium),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(
                  recorte.png,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
                      const SizedBox(
                        height: 120,
                        child: Center(child: Icon(Icons.broken_image_outlined)),
                      ),
                ),
              ),
              if (recorte.variosRostros) ...<Widget>[
                const SizedBox(height: 12),
                const Text(
                  'Salía más de una persona. Usamos el rostro más grande.',
                ),
              ],
              if (recomendaciones.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                Card(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('Podría salir mejor', style: texto.titleSmall),
                        const SizedBox(height: 4),
                        for (final String r in recomendaciones) Text('• $r'),
                        const SizedBox(height: 4),
                        const Text(
                          'Puedes repetirla o usarla igual: tú decides.',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: onRepetir,
                  child: const Text('Repetir'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: onUsar,
                  child: const Text('Usar esta foto'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({
    required this.icono,
    required this.titulo,
    required this.texto,
    required this.accion,
  });

  final IconData icono;
  final String titulo;
  final String texto;
  final Widget accion;

  @override
  Widget build(BuildContext context) {
    final TextTheme tema = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icono, size: 48),
            const SizedBox(height: 12),
            Text(titulo, style: tema.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(texto, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            accion,
          ],
        ),
      ),
    );
  }
}
