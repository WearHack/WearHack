/// Piezas falsas para probar la cola de captura sin disco, sin modelos y sin
/// red.
library;

import 'dart:typed_data';

import 'package:wearhack/core/atributos_c18.dart';
import 'package:wearhack/core/vocabulario.dart';
import 'package:wearhack/features/closet/captura/almacen_cola.dart';
import 'package:wearhack/features/closet/captura/cola_captura.dart';
import 'package:wearhack/features/closet/captura/item_cola.dart';
import 'package:wearhack/platform/captura/contratos.dart';

/// El almacen en memoria. Imita al de archivos, incluido que leer algo que no
/// existe falla, y guarda el orden de las escrituras para probar que la cola no
/// pierde fotos.
class AlmacenEnMemoria implements AlmacenCola {
  List<ItemCola> indice = <ItemCola>[];
  final Map<String, Uint8List> originales = <String, Uint8List>{};
  final Map<String, Uint8List> procesadas = <String, Uint8List>{};

  /// Cada escritura o borrado, en orden: `original:ID`, `indice`, `borrar:ID`.
  final List<String> bitacora = <String>[];

  @override
  Future<List<ItemCola>> cargar() async => List<ItemCola>.of(indice);

  @override
  Future<void> guardarIndice(List<ItemCola> items) async {
    bitacora.add('indice');
    indice = List<ItemCola>.of(items);
  }

  @override
  Future<void> guardarOriginal(String id, Uint8List bytes) async {
    bitacora.add('original:$id');
    originales[id] = bytes;
  }

  @override
  Future<Uint8List> leerOriginal(String id) async =>
      originales[id] ?? (throw ArchivoDeColaFaltante(id, 'la original'));

  @override
  Future<void> guardarProcesada(String id, Uint8List png) async {
    bitacora.add('procesada:$id');
    procesadas[id] = png;
  }

  @override
  Future<Uint8List> leerProcesada(String id) async =>
      procesadas[id] ?? (throw ArchivoDeColaFaltante(id, 'la procesada'));

  @override
  Future<void> borrarArchivos(String id) async {
    bitacora.add('borrar:$id');
    originales.remove(id);
    procesadas.remove(id);
  }
}

PrendaClasificada prendaDeEjemplo({int marca = 0}) => PrendaClasificada(
  imagenSinFondo: Uint8List.fromList(<int>[137, 80, 78, 71, marca]),
  tipo: TipoC18.camiseta,
  confianzaTipo: 0.9,
  patron: PatronC18.liso,
  confianzaPatron: 0.8,
  color: const ColorLab(l: 50, a: 10, b: -20),
  categoriaColor: CategoriaColor.azul,
);

/// Un procesador que anota cada lote que recibe.
class ProcesadorFalso implements ProcesadorDePrendas {
  /// Los tamanos de cada lote, en orden.
  final List<int> lotes = <int>[];

  /// Los ids o marcas de las fotos que fallan: la foto cuyo primer byte esta
  /// aqui falla.
  final Set<int> fallanLasQueEmpiezanPor = <int>{};

  /// Si es `true`, todo el lote falla de golpe.
  bool fallaTodo = false;

  @override
  Future<List<ResultadoPrenda>> procesarLote(List<Uint8List> fotos) async {
    lotes.add(fotos.length);
    if (fallaTodo) throw StateError('el pipeline se cayo');
    return <ResultadoPrenda>[
      for (final Uint8List f in fotos)
        if (fallanLasQueEmpiezanPor.contains(f.first))
          PrendaFallida(StateError('no se pudo con la foto ${f.first}'))
        else
          PrendaProcesada(prendaDeEjemplo(marca: f.first)),
    ];
  }
}

/// Un subidor que decide, en cada llamada, si sube, no hay red o falla.
class SubidorFalso implements SubidorDePrendas {
  /// Los ids subidos, en orden.
  final List<String> subidos = <String>[];

  /// Cuantas veces se llamo, haya salido bien o mal.
  int llamadas = 0;

  /// Las proximas respuestas, una por llamada. Si se acaban, sube bien.
  final List<Object?> guion = <Object?>[];

  @override
  Future<void> subir(String id, PrendaClasificada prenda) async {
    llamadas++;
    if (guion.isNotEmpty) {
      final Object? siguiente = guion.removeAt(0);
      if (siguiente != null) throw siguiente;
    }
    subidos.add(id);
  }
}

class TermicoFalso implements EstadoTermico {
  TermicoFalso({this.caliente = false});

  @override
  bool caliente;
}

/// Un reloj que solo avanza cuando se lo pides.
class RelojFalso {
  RelojFalso([DateTime? inicio])
    : _ahora = inicio ?? DateTime.utc(2026, 10, 26);

  DateTime _ahora;

  DateTime call() => _ahora;

  void avanzar(Duration d) => _ahora = _ahora.add(d);
}

/// Una foto cuyo primer byte es [marca], para saber cual es cual.
Uint8List foto(int marca) => Uint8List.fromList(<int>[marca, 1, 2, 3]);
