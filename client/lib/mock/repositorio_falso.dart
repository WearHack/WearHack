/// Backend en memoria para maquetar sin levantar el docker compose.
///
/// Implementa los mismos contratos que implementara el cliente HTTP real, con
/// una latencia simulada para que los estados de carga se vean. Los cambios
/// (eliminar una prenda, reasignar un dia) duran lo que dura la app abierta.
library;

import 'package:wearhack/features/closet/prenda.dart';
import 'package:wearhack/features/closet/repositorio_closet.dart';
import 'package:wearhack/features/colorimetria/consentimiento.dart';
import 'package:wearhack/features/colorimetria/repositorio_consentimiento.dart';
import 'package:wearhack/features/outfits/contexto.dart';
import 'package:wearhack/features/outfits/outfit.dart';
import 'package:wearhack/features/outfits/repositorio_clima.dart';
import 'package:wearhack/features/outfits/repositorio_outfits.dart';
import 'package:wearhack/features/publicidad/catalogo.dart';
import 'package:wearhack/features/publicidad/repositorio_publicidad.dart';
import 'package:wearhack/mock/datos_falsos.dart';
import 'package:wearhack/mock/datos_publicidad.dart';

class RepositorioFalso
    implements
        ClosetConBorrado,
        RepositorioOutfits,
        RepositorioClima,
        RepositorioPublicidad,
        RepositorioConsentimiento {
  RepositorioFalso({
    DateTime? hoy,
    this.latencia = const Duration(milliseconds: 300),
    this.temperatura = 18,
    this._consentimiento,
  }) : _hoy = _medianoche(hoy ?? DateTime.now()),
       _lunes = _lunesDe(hoy ?? DateTime.now());

  /// Lo que tarda cada respuesta. En los tests va a cero.
  final Duration latencia;

  /// La que devuelve [temperaturaEn] para cualquier lugar. 18 grados, como un
  /// dia normal en Bogota, cae en templado.
  final double? temperatura;

  final DateTime _hoy;
  final DateTime _lunes;
  String? _elegidoHoy;
  Consentimiento? _consentimiento;

  /// Los lotes generados hoy, por id, con los ids de sus opciones.
  final Map<String, List<String>> _lotes = <String, List<String>>{};

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
  Future<LoteOpciones> opcionesDeHoy(ContextoOutfit contexto) => _responder(() {
    final String id =
        'lote-${_hoy.year}-${_hoy.month}-${_hoy.day}-${contexto.clave}';
    // Filtros duros, como los aplicaria el Core: la formalidad que admite la
    // ocasion y, si hay dato, el clima. El mood no se simula: es un termino del
    // score, y aqui no hay score.
    final List<Outfit> opciones = <Outfit>[
      for (final String candidata in candidatasDeEjemplo)
        if (_buscar(candidata) case final Outfit o)
          if (contexto.ocasion.admite(o.formalidad) &&
              (contexto.clima == null || o.clima == contexto.clima))
            o,
    ].take(3).toList();
    _lotes[id] = <String>[for (final Outfit o in opciones) o.id];
    return LoteOpciones(
      id: id,
      fecha: _hoy,
      contexto: contexto,
      opciones: opciones,
      elegidoId: _elegidoHoy,
      elegido: _buscar(_elegidoHoy),
    );
  });

  @override
  Future<void> elegir(String loteId, String outfitId) => _responder(() {
    final List<String>? lote = _lotes[loteId];
    if (lote == null) {
      throw ArgumentError.value(loteId, 'loteId', 'no existe');
    }
    if (!lote.contains(outfitId)) {
      throw ArgumentError.value(outfitId, 'outfitId', 'no esta en el lote');
    }
    if (_elegidoHoy != null) {
      throw StateError('hoy ya se eligio $_elegidoHoy');
    }
    _elegidoHoy = outfitId;
    _plan[_indiceDe(_hoy)] = outfitId;
  });

  @override
  Future<double?> temperaturaEn({
    required double latitud,
    required double longitud,
  }) => _responder(() => temperatura);

  @override
  Future<Consentimiento?> consentimientoColorimetria() =>
      _responder(() => _consentimiento);

  @override
  Future<void> registrar(DecisionConsentimiento decision, int version) =>
      _responder(() {
        _consentimiento = Consentimiento(
          decision: decision,
          version: version,
          fecha: DateTime.now(),
        );
      });

  @override
  Future<void> revocar() => _responder(() {
    _consentimiento = null;
  });

  @override
  Future<List<MarcaAliada>> marcas() =>
      _responder(() => List<MarcaAliada>.unmodifiable(marcasDeEjemplo));

  @override
  Future<List<ProductoCatalogo>> catalogo(String marcaId) => _responder(
    () => <ProductoCatalogo>[
      for (final ProductoCatalogo p in catalogoDeEjemplo)
        if (p.marca.id == marcaId) p,
    ],
  );

  @override
  Future<List<PrendaPuente>> prendasPuente() => _responder(() {
    final Set<String> enCloset = <String>{
      for (final Prenda p in _prendas) p.id,
    };
    return <PrendaPuente>[
      for (final PrendaPuente puente in prendasPuenteDeEjemplo)
        if (puente.combinacionesBuenas >= umbralPrendaPuente)
          PrendaPuente(
            producto: puente.producto,
            combinacionesBuenas: puente.combinacionesBuenas,
            ocasionesNuevas: puente.ocasionesNuevas,
            // Sin las combinaciones que usan prendas ya eliminadas. El job
            // nocturno recalcularia tambien el numero; el mock no.
            ejemplos: <Outfit>[
              for (final Outfit o in puente.ejemplos)
                if (o.prendas.values.every(
                  (Prenda p) =>
                      p.id == puente.producto.id || enCloset.contains(p.id),
                ))
                  o,
            ],
          ),
    ];
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
