/// Backend en memoria para maquetar sin levantar el docker compose.
///
/// Implementa los mismos contratos que implementara el cliente HTTP real, con
/// una latencia simulada para que los estados de carga se vean. Los cambios
/// (eliminar una prenda, reasignar un dia) duran lo que dura la app abierta.
library;

import 'package:wearhack/features/closet/prenda.dart';
import 'package:wearhack/features/closet/repositorio_closet.dart';
import 'package:wearhack/features/outfits/outfit.dart';
import 'package:wearhack/features/outfits/repositorio_outfits.dart';
import 'package:wearhack/mock/datos_falsos.dart';

class RepositorioFalso implements RepositorioCloset, RepositorioOutfits {
  RepositorioFalso({
    DateTime? hoy,
    this.latencia = const Duration(milliseconds: 300),
  }) : _hoy = _medianoche(hoy ?? DateTime.now()),
       _lunes = _lunesDe(hoy ?? DateTime.now());

  /// Lo que tarda cada respuesta. En los tests va a cero.
  final Duration latencia;

  final DateTime _hoy;
  final DateTime _lunes;
  String? _elegidoHoy;

  String get _loteDeHoy => 'lote-${_hoy.year}-${_hoy.month}-${_hoy.day}';

  static DateTime _medianoche(DateTime dia) =>
      DateTime(dia.year, dia.month, dia.day);
  final List<Prenda> _prendas = List<Prenda>.of(prendasDeEjemplo);
  final List<Outfit> _outfits = List<Outfit>.of(outfitsDeEjemplo);
  final List<String?> _plan = List<String?>.of(planDeEjemplo);

  static DateTime _lunesDe(DateTime dia) =>
      DateTime(dia.year, dia.month, dia.day - (dia.weekday - 1));

  Future<T> _responder<T>(T Function() respuesta) async {
    await Future<void>.delayed(latencia);
    return respuesta();
  }

  @override
  Future<List<Prenda>> prendas() =>
      _responder(() => List<Prenda>.unmodifiable(_prendas));

  @override
  Future<void> eliminarPrenda(String id) => _responder(() {
    _prendas.removeWhere((Prenda p) => p.id == id);
    // El backend regeneraria los outfits. Aqui basta con quitar los que la
    // usaban y liberar los dias que los tenian.
    final Set<String> sinPrenda = <String>{
      for (final Outfit o in _outfits)
        if (o.prendas.values.any((Prenda p) => p.id == id)) o.id,
    };
    _outfits.removeWhere((Outfit o) => sinPrenda.contains(o.id));
    for (int i = 0; i < _plan.length; i++) {
      if (sinPrenda.contains(_plan[i])) _plan[i] = null;
    }
  });

  @override
  Future<List<Outfit>> outfitsDeLaSemana() =>
      _responder(() => List<Outfit>.unmodifiable(_outfits));

  @override
  Future<List<DiaPlan>> planSemanal() => _responder(
    () => <DiaPlan>[
      for (int i = 0; i < 7; i++)
        DiaPlan(
          fecha: DateTime(_lunes.year, _lunes.month, _lunes.day + i),
          outfit: _buscar(_plan[i]),
        ),
    ],
  );

  @override
  Future<void> asignarOutfit(DateTime dia, String? outfitId) => _responder(() {
    final int indice = _indiceDe(dia);
    if (outfitId != null && _buscar(outfitId) == null) {
      throw ArgumentError.value(outfitId, 'outfitId', 'no existe');
    }
    _plan[indice] = outfitId;
  });

  @override
  Future<LoteOpciones> opcionesDeHoy() => _responder(
    () => LoteOpciones(
      id: _loteDeHoy,
      fecha: _hoy,
      // Si se elimino una prenda, sus outfits ya no estan y el lote se queda
      // con menos opciones. El backend generaria otras; aqui basta con eso.
      opciones: <Outfit>[
        for (final String id in opcionesDeEjemplo)
          if (_buscar(id) case final Outfit o) o,
      ],
      elegidoId: _elegidoHoy,
    ),
  );

  @override
  Future<void> elegir(String loteId, String outfitId) => _responder(() {
    if (loteId != _loteDeHoy) {
      throw ArgumentError.value(loteId, 'loteId', 'no existe');
    }
    if (!opcionesDeEjemplo.contains(outfitId) || _buscar(outfitId) == null) {
      throw ArgumentError.value(outfitId, 'outfitId', 'no esta en el lote');
    }
    if (_elegidoHoy != null) {
      throw StateError('el lote $loteId ya tiene una eleccion');
    }
    _elegidoHoy = outfitId;
    _plan[_indiceDe(_hoy)] = outfitId;
  });

  Outfit? _buscar(String? id) =>
      id == null ? null : _outfits.where((Outfit o) => o.id == id).firstOrNull;

  int _indiceDe(DateTime dia) {
    final DateTime medianoche = DateTime(dia.year, dia.month, dia.day);
    // En horas y redondeando: un cambio de horario deja dias de 23 o 25 horas,
    // y `inDays` truncaria mal.
    final int indice = (medianoche.difference(_lunes).inHours / 24).round();
    if (indice < 0 || indice > 6) {
      throw ArgumentError.value(dia, 'dia', 'fuera de la semana en curso');
    }
    return indice;
  }
}
