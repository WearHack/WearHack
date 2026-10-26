/// La cola de captura de prendas y la cola de subida (issue #11).
///
/// Lo que garantiza, y como:
///
/// - **Disparar es barato.** [ColaCaptura.encolar] solo guarda la foto y el
///   indice y vuelve. El procesamiento corre aparte, en [ColaCaptura.arrancar].
/// - **Cero fotos perdidas.** La foto se guarda *antes* que el indice, y la
///   subida confirmada saca el elemento del indice *antes* de borrar archivos.
///   Ver `almacen_cola.dart`.
/// - **Sobrevive al cierre.** Solo se guardan estados estables; lo que estaba
///   "a medias" se repite al abrir (ver `item_cola.dart`).
/// - **Tope de pendientes.** Pasado [ConfiguracionCola.maxPendientes], encolar
///   falla con [ColaLlena] y no escribe nada.
/// - **Lotes de ~5.** El procesador recibe hasta [ConfiguracionCola.tamanoLote]
///   fotos de una vez, para que un pipeline por etapas cargue cada modelo una
///   sola vez por lote.
/// - **Subida aparte y tolerante a la red.** Un [SinConexion] no cuenta como
///   intento de la foto: se espera con retroceso exponencial y se reintenta. La
///   foto original se borra solo cuando el servidor confirma.
/// - **Pausa por calor.** Si [EstadoTermico.caliente], no se procesa; la subida
///   sigue, que casi no gasta.
///
/// **Que no hace todavia:** no hay pantalla, ni subidor real (necesita el
/// cliente HTTP), ni sensor de temperatura real. Los tres entran como interfaces.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:wearhack/features/closet/captura/almacen_cola.dart';
import 'package:wearhack/features/closet/captura/item_cola.dart';
import 'package:wearhack/platform/captura/contratos.dart';

// ---------------------------------------------------------------------------
// Piezas que entran por fuera
// ---------------------------------------------------------------------------

/// El resultado de una foto dentro de un lote.
sealed class ResultadoPrenda {
  const ResultadoPrenda();
}

final class PrendaProcesada extends ResultadoPrenda {
  const PrendaProcesada(this.prenda);
  final PrendaClasificada prenda;
}

final class PrendaFallida extends ResultadoPrenda {
  const PrendaFallida(this.error);
  final Object error;
}

/// Procesa fotos de prenda por lotes.
///
/// Es el punto donde #12 y #13 conectan su pipeline por etapas: quitar el
/// fondo de las N fotos con u2netp cargado una vez, liberarlo, y luego
/// clasificar las N con el otro modelo. Aqui solo se pide el contrato.
abstract interface class ProcesadorDePrendas {
  /// Una respuesta por foto y **en el mismo orden**. El fallo de una foto no
  /// debe tumbar a las demas: se devuelve como [PrendaFallida].
  Future<List<ResultadoPrenda>> procesarLote(List<Uint8List> fotos);
}

/// Adapta el [GarmentPipeline] actual al contrato de lotes.
///
/// Es la version ingenua: prepara una vez por lote, procesa de una en una y
/// libera al final. No carga cada modelo una sola vez por lote; eso lo hara el
/// pipeline por etapas de #12 y #13 cuando exista.
class ProcesadorSobrePipeline implements ProcesadorDePrendas {
  ProcesadorSobrePipeline(this._pipeline);

  final GarmentPipeline _pipeline;

  @override
  Future<List<ResultadoPrenda>> procesarLote(List<Uint8List> fotos) async {
    try {
      await _pipeline.preparar();
    } on Object catch (e) {
      return <ResultadoPrenda>[for (final _ in fotos) PrendaFallida(e)];
    }
    final List<ResultadoPrenda> resultados = <ResultadoPrenda>[];
    try {
      for (final Uint8List foto in fotos) {
        try {
          resultados.add(PrendaProcesada(await _pipeline.procesar(foto)));
        } on Object catch (e) {
          resultados.add(PrendaFallida(e));
        }
      }
    } finally {
      try {
        await _pipeline.liberar();
      } on Object {
        // Soltar memoria no debe perder lo ya procesado.
      }
    }
    return resultados;
  }
}

/// Sube una prenda ya procesada.
abstract interface class SubidorDePrendas {
  /// [id] es la llave de idempotencia: subir dos veces el mismo id debe dejar
  /// una sola prenda. Lanza [SinConexion] si no hay red; cualquier otro error se
  /// cuenta como intento fallido de esa foto.
  Future<void> subir(String id, PrendaClasificada prenda);
}

/// No hay red (o el servidor no responde). No es culpa de la foto.
class SinConexion implements Exception {
  const SinConexion([this.detalle = '']);
  final String detalle;

  @override
  String toString() => 'SinConexion: $detalle';
}

/// Si el telefono esta demasiado caliente para seguir procesando.
abstract interface class EstadoTermico {
  bool get caliente;
}

/// Sin sensor: nunca esta caliente.
class SinControlTermico implements EstadoTermico {
  const SinControlTermico();

  @override
  bool get caliente => false;
}

// ---------------------------------------------------------------------------
// Configuracion y errores
// ---------------------------------------------------------------------------

class ConfiguracionCola {
  const ConfiguracionCola({
    this.maxPendientes = 50,
    this.tamanoLote = 5,
    this.maxIntentos = 5,
    this.esperaBase = const Duration(seconds: 2),
    this.esperaMax = const Duration(minutes: 5),
    this.pausaTermica = const Duration(seconds: 30),
  }) : assert(maxPendientes > 0),
       assert(tamanoLote > 0),
       assert(maxIntentos > 0);

  /// Fotos que esperan (por procesar o por subir). Las fallidas no cuentan: ya
  /// no avanzan solas.
  final int maxPendientes;

  final int tamanoLote;

  /// Intentos fallidos de una foto antes de marcarla [EstadoItem.fallida].
  final int maxIntentos;

  /// Espera tras el primer fallo; se duplica con cada uno, hasta [esperaMax].
  final Duration esperaBase;
  final Duration esperaMax;

  /// Cuanto esperar antes de volver a mirar la temperatura.
  final Duration pausaTermica;

  /// Retroceso exponencial: [esperaBase], el doble, el doble... tope [esperaMax].
  Duration retroceso(int fallos) {
    if (fallos <= 0) return Duration.zero;
    // El tope de 20 evita desbordar el desplazamiento con muchos fallos.
    final int potencia = fallos - 1 > 20 ? 20 : fallos - 1;
    final Duration espera = esperaBase * (1 << potencia);
    return espera > esperaMax ? esperaMax : espera;
  }
}

/// Se llego al tope de fotos pendientes.
class ColaLlena implements Exception {
  const ColaLlena(this.tope);
  final int tope;

  @override
  String toString() =>
      'ColaLlena: ya hay $tope fotos esperando. Espera a que se procesen.';
}

// ---------------------------------------------------------------------------
// La cola
// ---------------------------------------------------------------------------

class ColaCaptura {
  ColaCaptura._({
    required this._almacen,
    required this._procesador,
    required this._subidor,
    required this._termico,
    required this.configuracion,
    required this._ahora,
    required this._esperar,
    required this._generarId,
    required this._automatica,
    required this._items,
  });

  /// Abre la cola leyendo lo que hubiera guardado de la ultima vez.
  ///
  /// [automatica] hace que [encolar] arranque el trabajo por si sola. Las
  /// pruebas la apagan para avanzar con [ronda], paso a paso.
  static Future<ColaCaptura> abrir({
    required AlmacenCola almacen,
    required ProcesadorDePrendas procesador,
    required SubidorDePrendas subidor,
    EstadoTermico termico = const SinControlTermico(),
    ConfiguracionCola configuracion = const ConfiguracionCola(),
    DateTime Function()? ahora,
    Future<void> Function(Duration)? esperar,
    String Function()? generarId,
    bool automatica = true,
  }) async {
    final List<ItemCola> guardados = await almacen.cargar();
    return ColaCaptura._(
      almacen: almacen,
      procesador: procesador,
      subidor: subidor,
      termico: termico,
      configuracion: configuracion,
      ahora: ahora ?? DateTime.now,
      esperar: esperar ?? (Duration d) => Future<void>.delayed(d),
      generarId: generarId ?? _idPorDefecto,
      automatica: automatica,
      items: List<ItemCola>.of(guardados),
    );
  }

  final ConfiguracionCola configuracion;

  final AlmacenCola _almacen;
  final ProcesadorDePrendas _procesador;
  final SubidorDePrendas _subidor;
  final EstadoTermico _termico;
  final DateTime Function() _ahora;
  final Future<void> Function(Duration) _esperar;
  final String Function() _generarId;
  final bool _automatica;

  final List<ItemCola> _items;
  final StreamController<List<ItemCola>> _cambios =
      StreamController<List<ItemCola>>.broadcast();

  /// Las escrituras del indice van en fila, para que dos no se pisen.
  Future<void> _escrituras = Future<void>.value();

  Future<void>? _bucle;
  bool _corriendo = false;
  bool _detenida = false;
  final Completer<void> _alDetener = Completer<void>();

  /// Fallos de red seguidos y hasta cuando no se intenta subir. Es de la cola
  /// entera, no de una foto: si no hay red, no la hay para ninguna.
  int _fallosDeRed = 0;
  DateTime? _sinRedHasta;

  /// El ultimo error inesperado del bucle (disco lleno, por ejemplo).
  Object? errorInterno;

  static int _contador = 0;
  static String _idPorDefecto() {
    final int micro = DateTime.now().microsecondsSinceEpoch;
    _contador = (_contador + 1) & 0xffff;
    return '${micro.toRadixString(36)}${_contador.toRadixString(36)}';
  }

  // -- Lo que ve la interfaz ------------------------------------------------

  List<ItemCola> get items => List<ItemCola>.unmodifiable(_items);

  /// Fotos que esperan: por procesar o por subir.
  int get pendientes => _items.where((ItemCola i) => i.pendiente).length;

  /// Se emite una lista nueva en cada cambio.
  Stream<List<ItemCola>> get cambios => _cambios.stream;

  // -- Acciones -------------------------------------------------------------

  /// Guarda la foto y la pone en cola. Es lo unico que corre al disparar.
  ///
  /// Lanza [ColaLlena] si ya hay [ConfiguracionCola.maxPendientes] esperando.
  Future<String> encolar(Uint8List foto) async {
    if (pendientes >= configuracion.maxPendientes) {
      throw ColaLlena(configuracion.maxPendientes);
    }
    final String id = _generarId();
    // Primero la foto, despues el indice: ver `almacen_cola.dart`.
    await _almacen.guardarOriginal(id, foto);
    _items.add(ItemCola.nuevo(id: id, creadoEn: _ahora()));
    await _persistir();
    _avisar();
    if (_automatica) arrancar();
    return id;
  }

  /// Pone en marcha el trabajo en segundo plano. Si ya corre, no hace nada.
  void arrancar() {
    if (_detenida || _corriendo) return;
    _corriendo = true;
    _bucle = _correr();
  }

  /// Termina cuando no queda nada por hacer. Con la red caida no termina nunca
  /// (sigue esperando para reintentar): para eso esta [detener].
  Future<void> reposo() async => await _bucle;

  /// Para el trabajo. Lo que estaba en cola queda guardado.
  Future<void> detener() async {
    _detenida = true;
    if (!_alDetener.isCompleted) _alDetener.complete();
    await _bucle;
  }

  /// Las fallidas vuelven a intentarse desde el paso que les faltaba.
  Future<void> reintentarFallidas() async {
    bool hubo = false;
    for (int i = 0; i < _items.length; i++) {
      if (_items[i].estado == EstadoItem.fallida) {
        _items[i] = _items[i].reintentable();
        hubo = true;
      }
    }
    if (!hubo) return;
    await _persistir();
    _avisar();
    if (_automatica) arrancar();
  }

  /// Quita una foto de la cola y borra sus archivos. Para las fallidas que la
  /// persona no quiere reintentar.
  Future<void> descartar(String id) async {
    final int i = _items.indexWhere((ItemCola x) => x.id == id);
    if (i < 0) return;
    _items.removeAt(i);
    await _persistir();
    await _almacen.borrarArchivos(id);
    _avisar();
  }

  /// Una pasada de trabajo: procesa un lote y sube lo que toque.
  ///
  /// Devuelve cuanto esperar antes de la siguiente, `Duration.zero` si ya hay
  /// mas por hacer, o `null` si no queda nada pendiente. Es publica para poder
  /// probar la cola paso a paso.
  Future<Duration?> ronda() async {
    bool bloqueadaPorCalor = false;
    final List<ItemCola> lote = _items
        .where(
          (ItemCola i) =>
              i.estado == EstadoItem.porProcesar &&
              !_vence(i).isAfter(_ahora()),
        )
        .take(configuracion.tamanoLote)
        .toList();
    if (lote.isNotEmpty) {
      if (_termico.caliente) {
        bloqueadaPorCalor = true;
      } else {
        await _procesar(lote);
      }
    }
    await _subir();
    return _espera(_termico.caliente || bloqueadaPorCalor);
  }

  // -- Por dentro -----------------------------------------------------------

  Future<void> _correr() async {
    try {
      while (!_detenida) {
        Duration? espera;
        try {
          espera = await ronda();
        } on Object catch (e) {
          // Un fallo de disco no debe matar el bucle ni perder fotos: se anota
          // y se vuelve a intentar mas tarde.
          errorInterno = e;
          espera = configuracion.esperaBase;
        }
        if (espera == null) {
          // Se vuelve a mirar *aqui*, sin ninguna espera de por medio: una foto
          // encolada mientras la ronda terminaba la veria `arrancar` con el
          // bucle todavia marcado como corriendo y no lo arrancaria. Con esta
          // comprobacion, o la ve el bucle o la ve `arrancar`.
          if (pendientes == 0) return;
          continue;
        }
        if (espera > Duration.zero) {
          await Future.any<void>(<Future<void>>[
            _esperar(espera),
            _alDetener.future,
          ]);
        }
      }
    } finally {
      _corriendo = false;
    }
  }

  /// Cuando le toca intentar a un elemento.
  DateTime _vence(ItemCola i) {
    final DateTime? ultimo = i.ultimoIntento;
    if (ultimo == null) return i.creadoEn;
    return ultimo.add(configuracion.retroceso(i.intentos));
  }

  Future<void> _procesar(List<ItemCola> lote) async {
    // Se leen las originales; una que falte no tumba el lote.
    final List<ItemCola> conFoto = <ItemCola>[];
    final List<Uint8List> fotos = <Uint8List>[];
    for (final ItemCola item in lote) {
      try {
        fotos.add(await _almacen.leerOriginal(item.id));
        conFoto.add(item);
      } on Object catch (e) {
        _actualizar(
          item.id,
          (ItemCola i) => i.conFallo(
            ahora: _ahora(),
            error: 'No se pudo leer la foto: $e',
            definitivo: true,
          ),
        );
      }
    }

    if (conFoto.isNotEmpty) {
      List<ResultadoPrenda> resultados;
      try {
        resultados = await _procesador.procesarLote(fotos);
        if (resultados.length != conFoto.length) {
          throw StateError(
            'El procesador devolvio ${resultados.length} resultados para '
            '${conFoto.length} fotos',
          );
        }
      } on Object catch (e) {
        resultados = <ResultadoPrenda>[
          for (final _ in conFoto) PrendaFallida(e),
        ];
      }

      for (int k = 0; k < conFoto.length; k++) {
        final String id = conFoto[k].id;
        switch (resultados[k]) {
          case PrendaProcesada(:final PrendaClasificada prenda):
            // El PNG va a disco antes de tocar el indice: si la app muere aqui,
            // la foto sigue "por procesar" y se rehace, sin perder nada.
            await _almacen.guardarProcesada(id, prenda.imagenSinFondo);
            _actualizar(
              id,
              (ItemCola i) => i.procesado(DatosPrenda.dePrenda(prenda)),
            );
          case PrendaFallida(:final Object error):
            _actualizar(
              id,
              (ItemCola i) => i.conFallo(
                ahora: _ahora(),
                error: '$error',
                definitivo: i.intentos + 1 >= configuracion.maxIntentos,
              ),
            );
        }
      }
    }
    await _persistir();
    _avisar();
  }

  Future<void> _subir() async {
    final List<ItemCola> porSubir = _items
        .where((ItemCola i) => i.estado == EstadoItem.porSubir)
        .toList();

    for (final ItemCola item in porSubir) {
      final DateTime ahora = _ahora();
      final DateTime? sinRed = _sinRedHasta;
      if (sinRed != null && ahora.isBefore(sinRed)) return;
      if (_vence(item).isAfter(ahora)) continue;

      final PrendaClasificada prenda;
      try {
        final DatosPrenda datos = item.datos!;
        prenda = datos.aPrenda(await _almacen.leerProcesada(item.id));
      } on Object {
        // Se perdio el PNG pero la original sigue: se vuelve a procesar.
        _actualizar(item.id, (ItemCola i) => i.aReprocesar());
        await _persistir();
        _avisar();
        continue;
      }

      try {
        await _subidor.subir(item.id, prenda);
      } on SinConexion {
        _fallosDeRed++;
        _sinRedHasta = _ahora().add(configuracion.retroceso(_fallosDeRed));
        return;
      } on Object catch (e) {
        _actualizar(
          item.id,
          (ItemCola i) => i.conFallo(
            ahora: _ahora(),
            error: '$e',
            definitivo: i.intentos + 1 >= configuracion.maxIntentos,
          ),
        );
        await _persistir();
        _avisar();
        continue;
      }

      // Confirmada. Primero sale del indice, despues se borran los archivos:
      // ver `almacen_cola.dart`.
      _fallosDeRed = 0;
      _sinRedHasta = null;
      _items.removeWhere((ItemCola i) => i.id == item.id);
      await _persistir();
      await _almacen.borrarArchivos(item.id);
      _avisar();
    }
  }

  /// Cuanto falta para la siguiente ronda, o `null` si no hay nada pendiente.
  Duration? _espera(bool caliente) {
    final DateTime ahora = _ahora();
    Duration? mejor;
    void candidato(Duration d) {
      final Duration c = d.isNegative ? Duration.zero : d;
      if (mejor == null || c < mejor!) mejor = c;
    }

    bool hay = false;
    for (final ItemCola i in _items) {
      if (!i.pendiente) continue;
      hay = true;
      if (i.estado == EstadoItem.porProcesar && caliente) {
        candidato(configuracion.pausaTermica);
        continue;
      }
      DateTime cuando = _vence(i);
      final DateTime? sinRed = _sinRedHasta;
      if (i.estado == EstadoItem.porSubir &&
          sinRed != null &&
          sinRed.isAfter(cuando)) {
        cuando = sinRed;
      }
      candidato(cuando.difference(ahora));
    }
    return hay ? mejor : null;
  }

  /// Cambia un elemento si todavia esta; pudo descartarse mientras se trabajaba.
  void _actualizar(String id, ItemCola Function(ItemCola) cambio) {
    final int i = _items.indexWhere((ItemCola x) => x.id == id);
    if (i >= 0) _items[i] = cambio(_items[i]);
  }

  Future<void> _persistir() {
    final List<ItemCola> instantanea = List<ItemCola>.of(_items);
    final Future<void> escritura = _escrituras.then(
      (_) => _almacen.guardarIndice(instantanea),
    );
    _escrituras = escritura.then((_) {}, onError: (Object _) {});
    return escritura;
  }

  void _avisar() {
    if (!_cambios.isClosed) _cambios.add(items);
  }
}
