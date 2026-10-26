/// Pantalla 3: la camara frontal, la guia, y el boton de tomar la foto.
///
/// Al pulsar el boton: se toma la foto, se llama al recorte real del producto
/// (a traves de `ServicioCapturaPruebas`) y se guarda todo. La pantalla no sabe
/// de archivos ni de recortes: solo muestra lo que le devuelve el servicio.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wearhack/core/color/perfil_icc.dart';
import 'package:wearhack/core/recorte/configuracion_recorte.dart';
import 'package:wearhack/core/recorte/controles_calidad.dart';
import 'package:wearhack/features/captura_pruebas/almacen_capturas.dart';
import 'package:wearhack/features/captura_pruebas/metadatos.dart';
import 'package:wearhack/features/captura_pruebas/modelos.dart';
import 'package:wearhack/features/captura_pruebas/servicio_captura.dart';
import 'package:wearhack/features/captura_pruebas/ui/camara.dart';
import 'package:wearhack/features/captura_pruebas/ui/dependencias.dart';
import 'package:wearhack/features/captura_pruebas/ui/guia_de_distancia.dart';
import 'package:wearhack/features/captura_pruebas/ui/sesion.dart';

class PantallaCaptura extends StatefulWidget {
  const PantallaCaptura({
    super.key,
    required this.dependencias,
    required this.sesion,
    required this.id,
    this.reemplazar = false,
  });

  final DependenciasCaptura dependencias;
  final SesionCaptura sesion;
  final IdToma id;

  /// `true` si ya existe esta toma y la nueva debe reemplazarla.
  final bool reemplazar;

  @override
  State<PantallaCaptura> createState() => _PantallaCapturaState();
}

enum _EstadoDeCamara { abriendo, lista, fallo }

class _PantallaCapturaState extends State<PantallaCaptura> {
  late final CamaraDeCaptura _camara = widget.dependencias.crearCamara();
  _EstadoDeCamara _estadoCamara = _EstadoDeCamara.abriendo;
  String? _errorDeCamara;

  bool _ocupado = false;
  String? _mensaje;
  late bool _reemplazar = widget.reemplazar;

  int? _anchoDelRostro;
  StreamSubscription<int?>? _suscripcion;

  @override
  void initState() {
    super.initState();
    _abrirCamara();
  }

  Future<void> _abrirCamara() async {
    try {
      await _camara.inicializar();
      if (!mounted) return;
      _suscripcion = _camara.anchoDelRostroEnVivo.listen(
        (int? ancho) {
          if (mounted) setState(() => _anchoDelRostro = ancho);
        },
        // Un fallo de la deteccion en vivo solo apaga la guia: no la captura.
        onError: (Object _) {},
      );
      setState(() => _estadoCamara = _EstadoDeCamara.lista);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _estadoCamara = _EstadoDeCamara.fallo;
        _errorDeCamara = e is SinCamaraFrontal
            ? 'Este celular no tiene camara frontal.'
            : 'No se pudo abrir la camara: $e';
      });
    }
  }

  @override
  void dispose() {
    _suscripcion?.cancel();
    _camara.liberar();
    super.dispose();
  }

  Future<void> _capturar() async {
    final DependenciasCaptura d = widget.dependencias;
    final SesionCaptura s = widget.sesion;
    setState(() {
      _ocupado = true;
      _mensaje = null;
    });
    try {
      final FotoTomada foto = await _camara.tomarFoto();
      final InfoDelDispositivo info = await d.dispositivo.leer();
      final ResultadoRegistro r = await d.servicio.registrarToma(
        id: widget.id,
        autorizacionFirmada: s.autorizacionFirmada,
        foto: foto.bytes,
        celular: DatosDelCelular(
          codigo: s.celular,
          modelo: info.modelo,
          sistema: info.sistema,
          buildApp: info.buildApp,
          trueToneONightShift: s.trueToneONightShift,
        ),
        momento: d.ahora(),
        extensionFoto: foto.extension,
        espejo: foto.espejo,
        reemplazar: _reemplazar,
      );
      if (!mounted) return;

      // La toma ya esta guardada. Si un control de calidad no paso, se sugiere
      // repetir con una recomendacion concreta, pero no se obliga.
      if (!r.controles.pasa) {
        final bool repetir = await _preguntarSiRepetir(r.controles);
        if (repetir) {
          _reemplazar = true; // ahora ya existe: la siguiente la reemplaza
          return;
        }
      }
      if (mounted) Navigator.of(context).pop(true);
    } on SinRostro {
      _decir('No se vio un rostro. Encuadra la cara en el ovalo y repite.');
    } on ConfiguracionRecorteInvalida catch (e) {
      _decir('Falta configurar el recorte: ${e.problemas.join('; ')}.');
    } on PerfilIccNoSoportado catch (e) {
      _decir(
        'La foto trae un perfil de color que no se sabe leer: ${e.motivo}',
      );
    } on TomaYaExiste {
      _decir('Esa toma ya existe. Vuelve a la cuadricula para reemplazarla.');
    } on Object catch (e) {
      _decir('No se pudo guardar la toma: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  void _decir(String texto) {
    if (mounted) setState(() => _mensaje = texto);
  }

  Future<bool> _preguntarSiRepetir(ControlesCalidad controles) async {
    final bool? repetir = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        key: const Key('dialogo_calidad'),
        title: const Text('La foto se guardo, pero se puede mejorar'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final String recomendacion in controles.recomendaciones)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(recomendacion),
              ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('conservar_toma'),
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Conservar'),
          ),
          FilledButton(
            key: const Key('repetir_toma'),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Repetir'),
          ),
        ],
      ),
    );
    return repetir ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final SesionCaptura s = widget.sesion;
    final RangoDeAncho? rango = widget.dependencias.rangoDeDistancia(s.celular);
    final EstadoDeDistancia distancia = clasificarDistancia(
      _anchoDelRostro,
      rango,
    );

    return Scaffold(
      appBar: AppBar(title: Text(widget.id.nombreBase)),
      body: switch (_estadoCamara) {
        _EstadoDeCamara.abriendo => const Center(
          child: CircularProgressIndicator(),
        ),
        _EstadoDeCamara.fallo => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _errorDeCamara ?? 'Error de camara',
              key: const Key('error_camara'),
            ),
          ),
        ),
        _EstadoDeCamara.lista => Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Center(child: _camara.vistaPrevia()),
            const IgnorePointer(child: CustomPaint(painter: _PintorDelOvalo())),
            Align(
              alignment: Alignment.topCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _Cartel(
                    key: const Key('aviso_tarjeta'),
                    texto: widget.id.repeticion.llevaTarjetaGris
                        ? 'Pon la tarjeta gris junto al rostro'
                        : 'Retira la tarjeta gris',
                  ),
                  _Cartel(
                    key: const Key('aviso_distancia'),
                    texto: _camara.guiaDeDistanciaActiva
                        ? textoDeDistancia(distancia, _anchoDelRostro)
                        : 'Guia de distancia apagada: 30-40 cm a ojo',
                  ),
                  if (_mensaje != null)
                    _Cartel(key: const Key('mensaje'), texto: _mensaje!),
                ],
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: FloatingActionButton.large(
                    key: const Key('boton_capturar'),
                    // Mientras se guarda no se acepta otra pulsacion.
                    onPressed: _ocupado ? null : _capturar,
                    child: _ocupado
                        ? const CircularProgressIndicator()
                        : const Icon(Icons.camera_alt),
                  ),
                ),
              ),
            ),
          ],
        ),
      },
    );
  }
}

class _Cartel extends StatelessWidget {
  const _Cartel({super.key, required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.black.withValues(alpha: 0.65),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(texto, style: const TextStyle(color: Colors.white)),
    );
  }
}

/// Oscurece todo menos un ovalo, para encuadrar el rostro.
class _PintorDelOvalo extends CustomPainter {
  const _PintorDelOvalo();

  @override
  void paint(Canvas canvas, Size size) {
    final Rect ovalo = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.45),
      width: size.width * 0.62,
      height: size.width * 0.62 * 1.35,
    );
    final Path fuera = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(ovalo);
    canvas.drawPath(
      fuera,
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    canvas.drawOval(
      ovalo,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
