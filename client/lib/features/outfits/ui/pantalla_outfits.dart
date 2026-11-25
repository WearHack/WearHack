/// Los outfits que el recomendador genero para esta semana.
///
/// Arriba, el panel de hoy: ocasion, mood y clima (issue #17) y la entrada a
/// elegir el outfit de hoy entre N opciones (issue #16). Debajo, la consulta de
/// los outfits de la semana (issue #15).
library;

import 'package:flutter/material.dart';
import 'package:wearhack/core/ui/estados.dart';
import 'package:wearhack/core/ui/etiquetas.dart';
import 'package:wearhack/core/ui/movimiento.dart';
import 'package:wearhack/core/vocabulario.dart';
import 'package:wearhack/features/closet/prenda.dart';
import 'package:wearhack/features/closet/ui/muestra_prenda.dart';
import 'package:wearhack/features/outfits/contexto.dart';
import 'package:wearhack/features/outfits/outfit.dart';
import 'package:wearhack/features/outfits/repositorio_clima.dart';
import 'package:wearhack/features/outfits/repositorio_outfits.dart';
import 'package:wearhack/features/outfits/ui/pantalla_elegir.dart';
import 'package:wearhack/features/outfits/ui/tarjeta_outfit.dart';
import 'package:wearhack/platform/ubicacion.dart';

class PantallaOutfits extends StatefulWidget {
  const PantallaOutfits({
    super.key,
    required this.repositorio,
    required this.clima,
    required this.ubicacion,
  });

  final RepositorioOutfits repositorio;
  final RepositorioClima? clima;
  final ServicioUbicacion ubicacion;

  @override
  State<PantallaOutfits> createState() => _PantallaOutfitsState();
}

enum _EstadoClima { sinPedir, buscando, obtenido, denegado, sinDato }

class _PantallaOutfitsState extends State<PantallaOutfits> {
  ContextoOutfit _contexto = const ContextoOutfit();
  _EstadoClima _estadoClima = _EstadoClima.sinPedir;
  double? _temperatura;

  late Future<(List<Outfit>, LoteOpciones)> _carga = _cargar();

  Future<(List<Outfit>, LoteOpciones)> _cargar() async {
    final LoteOpciones lote = await widget.repositorio.opcionesDeHoy(_contexto);
    return (await widget.repositorio.outfitsDeLaSemana(), lote);
  }

  void _recargar() {
    setState(() {
      _carga = _cargar();
    });
  }

  void _cambiarContexto(ContextoOutfit contexto) {
    setState(() {
      _contexto = contexto;
      _carga = _cargar();
    });
  }

  Future<void> _usarUbicacion() async {
    final RepositorioClima? clima = widget.clima;
    if (clima == null) return;
    setState(() => _estadoClima = _EstadoClima.buscando);

    double? temperatura;
    _EstadoClima estado;
    switch (await widget.ubicacion.obtener()) {
      case UbicacionObtenida(:final double latitud, :final double longitud):
        try {
          // Dos decimales son ~1 km: de sobra para el clima, y la posicion
          // exacta del usuario no sale del dispositivo.
          temperatura = await clima.temperaturaEn(
            latitud: _redondear(latitud),
            longitud: _redondear(longitud),
          );
        } on Object {
          temperatura = null;
        }
        estado = temperatura == null
            ? _EstadoClima.sinDato
            : _EstadoClima.obtenido;
      case UbicacionDenegada():
        estado = _EstadoClima.denegado;
      case UbicacionNoDisponible():
        estado = _EstadoClima.sinDato;
    }
    if (!mounted) return;

    _estadoClima = estado;
    _temperatura = temperatura;
    _cambiarContexto(
      _contexto.conClima(temperatura == null ? null : climaPara(temperatura)),
    );
  }

  static double _redondear(double grados) => (grados * 100).round() / 100;

  Future<void> _elegir(LoteOpciones lote) async {
    final bool? eligio = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            PantallaElegir(repositorio: widget.repositorio, lote: lote),
      ),
    );
    if (eligio != true || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Listo, ese es tu outfit de hoy')),
    );
    _recargar();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(List<Outfit>, LoteOpciones)>(
      future: _carga,
      builder:
          (
            BuildContext context,
            AsyncSnapshot<(List<Outfit>, LoteOpciones)> snapshot,
          ) {
            if (snapshot.hasError) return ErrorDeCarga(onReintentar: _recargar);
            final (List<Outfit>, LoteOpciones)? datos = snapshot.data;
            if (datos == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final (List<Outfit> outfits, LoteOpciones lote) = datos;

            // En web la ventana puede ser muy ancha; una columna de tarjetas
            // estiradas a 1900 px no se lee.
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    if (lote.elegidoId != null)
                      _OutfitElegido(elegido: lote.elegido)
                    else
                      _PanelDeHoy(
                        contexto: _contexto,
                        lote: lote,
                        estadoClima: _estadoClima,
                        temperatura: _temperatura,
                        ofrecerClima: widget.clima != null,
                        ubicacionDisponible: widget.ubicacion.disponible,
                        onContexto: _cambiarContexto,
                        onUbicacion: _usarUbicacion,
                        onElegir: () => _elegir(lote),
                      ),
                    const SizedBox(height: 16),
                    if (outfits.isEmpty)
                      const MensajeVacio(
                        icono: Icons.style_outlined,
                        texto: 'Todavía no hay outfits para esta semana.',
                      )
                    else ...<Widget>[
                      Text(
                        'Generados a partir de tu clóset para esta semana.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      for (final (int i, Outfit o)
                          in outfits.indexed) ...<Widget>[
                        const SizedBox(height: 8),
                        Aparece(
                          key: ValueKey<String>(o.id),
                          indice: i,
                          child: TarjetaOutfit(outfit: o),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            );
          },
    );
  }
}

/// Ocasion, mood y clima de hoy, y el boton para elegir entre las opciones.
class _PanelDeHoy extends StatelessWidget {
  const _PanelDeHoy({
    required this.contexto,
    required this.lote,
    required this.estadoClima,
    required this.temperatura,
    required this.ofrecerClima,
    required this.ubicacionDisponible,
    required this.onContexto,
    required this.onUbicacion,
    required this.onElegir,
  });

  final ContextoOutfit contexto;
  final LoteOpciones lote;
  final _EstadoClima estadoClima;
  final double? temperatura;
  final bool ofrecerClima;
  final bool ubicacionDisponible;
  final ValueChanged<ContextoOutfit> onContexto;
  final VoidCallback onUbicacion;
  final VoidCallback onElegir;

  @override
  Widget build(BuildContext context) {
    final TextTheme texto = Theme.of(context).textTheme;
    final int n = lote.opciones.length;

    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('¿Qué te pones hoy?', style: texto.titleMedium),
            const SizedBox(height: 12),
            Text('Ocasión', style: texto.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                for (final Ocasion o in Ocasion.values)
                  ChoiceChip(
                    label: Text(o.etiqueta),
                    tooltip: o.ejemplos,
                    selected: contexto.ocasion == o,
                    onSelected: (_) => onContexto(contexto.conOcasion(o)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Mood (opcional)', style: texto.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                for (final Mood m in Mood.values)
                  ChoiceChip(
                    label: Text(m.etiqueta),
                    selected: contexto.mood == m,
                    // Tocar el mood marcado lo quita: es opcional.
                    onSelected: (bool marcado) =>
                        onContexto(contexto.conMood(marcado ? m : null)),
                  ),
              ],
            ),
            if (ofrecerClima) ...<Widget>[
              const SizedBox(height: 12),
              Text('Clima', style: texto.labelLarge),
              const SizedBox(height: 4),
              _FilaClima(
                estado: estadoClima,
                clima: contexto.clima,
                temperatura: temperatura,
                ubicacionDisponible: ubicacionDisponible,
                onUbicacion: onUbicacion,
              ),
            ],
            const Divider(height: 32),
            if (n >= 2)
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Elige entre $n opciones pensadas para ti.',
                      style: texto.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: onElegir,
                    child: const Text('Elegir'),
                  ),
                ],
              )
            else
              // Con menos de dos no hay nada que comparar, y una eleccion sin
              // descartados no ensena nada.
              Text(
                n == 1
                    ? 'Hay una combinación. Puedes asignarla en Mi semana.'
                    : 'No hay suficientes outfits para esta ocasión. '
                          'Agrega calzado y prendas para arriba y abajo, '
                          'o un vestido o enterizo.',
                style: texto.bodyMedium,
              ),
          ],
        ),
      ),
    );
  }
}

class _FilaClima extends StatelessWidget {
  const _FilaClima({
    required this.estado,
    required this.clima,
    required this.temperatura,
    required this.ubicacionDisponible,
    required this.onUbicacion,
  });

  final _EstadoClima estado;
  final Clima? clima;
  final double? temperatura;
  final bool ubicacionDisponible;
  final VoidCallback onUbicacion;

  @override
  Widget build(BuildContext context) {
    final Clima? c = clima;
    final double? t = temperatura;

    final (IconData icono, String mensaje) = switch (estado) {
      _ when !ubicacionDisponible => (
        Icons.location_off_outlined,
        'Este dispositivo no permite usar tu ubicación. Las opciones no '
            'tienen en cuenta el clima.',
      ),
      _EstadoClima.sinPedir => (
        Icons.cloud_outlined,
        'Usa tu ubicación para tener en cuenta el clima de tu zona.',
      ),
      _EstadoClima.buscando => (
        Icons.my_location,
        'Buscando el clima de tu zona…',
      ),
      _EstadoClima.obtenido when c != null && t != null => (
        c.icono,
        '${c.etiqueta} · ${t.round()} °C en tu zona',
      ),
      _EstadoClima.denegado => (
        Icons.location_off_outlined,
        'No diste permiso de ubicación. Las opciones no tienen en cuenta el '
            'clima.',
      ),
      _ => (
        Icons.cloud_off_outlined,
        'No se pudo obtener el clima. Las opciones no lo tienen en cuenta.',
      ),
    };

    return Row(
      children: <Widget>[
        Icon(icono, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(mensaje)),
        if (ubicacionDisponible && estado != _EstadoClima.buscando) ...<Widget>[
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: onUbicacion,
            icon: const Icon(Icons.my_location, size: 18),
            label: Text(
              estado == _EstadoClima.sinPedir
                  ? 'Usar mi ubicación'
                  : 'Actualizar',
            ),
          ),
        ],
      ],
    );
  }
}

class _OutfitElegido extends StatelessWidget {
  const _OutfitElegido({required this.elegido});

  /// Puede faltar si despues se elimino una de sus prendas.
  final Outfit? elegido;

  @override
  Widget build(BuildContext context) {
    final TextTheme texto = Theme.of(context).textTheme;
    final Outfit? e = elegido;

    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Tu outfit de hoy', style: texto.titleMedium),
            const SizedBox(height: 4),
            Text('Ya elegiste el outfit de hoy.', style: texto.bodyMedium),
            if (e != null) ...<Widget>[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (final Prenda p in e.prendasEnOrden)
                    MuestraPrenda(prenda: p, tamano: 40),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                e.prendasEnOrden.map((Prenda p) => p.tipo.etiqueta).join(' · '),
                style: texto.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
