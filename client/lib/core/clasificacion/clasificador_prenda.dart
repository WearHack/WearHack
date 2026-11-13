/// Lo que rodea al clasificador de prendas (issue #13) y no depende de LiteRT:
/// preparar la entrada y leer las salidas.
///
/// El modelo es `prendas-v1`: MobileNetV3-Small con dos cabezas, tipo y patron
/// (ver `assets/models/README.md`). La textura no se clasifica en el MVP.
///
/// El preproceso tiene que ser **el mismo del entrenamiento**
/// (`a_cuadrado` en `tools/entrenamiento/prendas/entrenar.py`): la prenda se
/// centra en un cuadrado blanco y se escala a 224 con interpolacion bilineal.
/// Si cambia alli, cambia aqui.
///
/// Solo Dart, sin plugins: corre igual en el telefono y en las pruebas.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:wearhack/core/atributos_c18.dart';

/// Lado de la entrada del modelo: `(1, 224, 224, 3)`, NHWC.
const int ladoEntradaClasificador = 224;

/// El orden de las clases de la cabeza de tipo. Es el de `TIPOS` en
/// `tools/entrenamiento/prendas/mapeo.py`, no el del enum: si alguien reordena
/// [TipoC18], el modelo no se entera.
const List<TipoC18> ordenTiposClasificador = <TipoC18>[
  TipoC18.camisa,
  TipoC18.camiseta,
  TipoC18.sueter,
  TipoC18.cardigan,
  TipoC18.chaqueta,
  TipoC18.abrigo,
  TipoC18.chaleco,
  TipoC18.pantalon,
  TipoC18.short,
  TipoC18.falda,
  TipoC18.vestido,
  TipoC18.enterizo,
  TipoC18.calzado,
  TipoC18.gafas,
  TipoC18.sombrero,
  TipoC18.accesorioCabello,
  TipoC18.corbata,
  TipoC18.bufanda,
  TipoC18.reloj,
  TipoC18.cinturon,
  TipoC18.bolso,
];

/// El orden de la cabeza de patron: `PATRONES` en `mapeo.py`.
const List<PatronC18> ordenPatronesClasificador = <PatronC18>[
  PatronC18.liso,
  PatronC18.rayas,
  PatronC18.cuadros,
  PatronC18.puntos,
  PatronC18.floral,
  PatronC18.animal,
  PatronC18.geometrico,
  PatronC18.otroEstampado,
];

/// Lo que sale del clasificador para una prenda.
///
/// Las confianzas son la probabilidad (softmax) de la clase elegida. El umbral
/// de "baja confianza" no esta definido (C.16): por ahora solo se informan.
class Clasificacion {
  const Clasificacion({
    required this.tipo,
    required this.confianzaTipo,
    required this.patron,
    required this.confianzaPatron,
  });

  final TipoC18 tipo;
  final double confianzaTipo;
  final PatronC18 patron;
  final double confianzaPatron;

  @override
  String toString() =>
      'Clasificacion(${tipo.codigo} ${confianzaTipo.toStringAsFixed(2)}, '
      '${patron.codigo} ${confianzaPatron.toStringAsFixed(2)})';
}

/// Clasifica una prenda ya sin fondo. La implementacion con LiteRT vive en la
/// rama movil de `lib/platform/captura/`.
abstract interface class ClasificadorDePrendas {
  Future<Clasificacion> clasificar(img.Image prendaSinFondo);
}

/// La entrada del modelo: RGB en `[0, 255]` como float32, sin normalizar (la
/// normalizacion va dentro del modelo).
///
/// Lo transparente se pinta de blanco, igual que el fondo con el que se
/// recortaron las prendas del entrenamiento; luego se centra en un cuadrado
/// blanco y se escala a 224.
Float32List entradaDelClasificador(img.Image prenda) {
  if (prenda.width == 0 || prenda.height == 0) {
    throw ArgumentError('La imagen de la prenda esta vacia');
  }
  final int lado = math.max(prenda.width, prenda.height);
  final img.Image lienzo = img.Image(width: lado, height: lado);
  img.fill(lienzo, color: img.ColorRgb8(255, 255, 255));
  // Mismo redondeo que PIL en a_cuadrado: division entera hacia abajo.
  img.compositeImage(
    lienzo,
    prenda,
    dstX: (lado - prenda.width) ~/ 2,
    dstY: (lado - prenda.height) ~/ 2,
  );
  final img.Image escalada = lado == ladoEntradaClasificador
      ? lienzo
      : img.copyResize(
          lienzo,
          width: ladoEntradaClasificador,
          height: ladoEntradaClasificador,
          interpolation: img.Interpolation.linear,
        );

  final Float32List entrada = Float32List(
    ladoEntradaClasificador * ladoEntradaClasificador * 3,
  );
  int i = 0;
  for (int y = 0; y < ladoEntradaClasificador; y++) {
    for (int x = 0; x < ladoEntradaClasificador; x++) {
      final img.Pixel p = escalada.getPixel(x, y);
      entrada[i++] = p.r.toDouble();
      entrada[i++] = p.g.toDouble();
      entrada[i++] = p.b.toDouble();
    }
  }
  return entrada;
}

/// Lee los logits de las dos cabezas. Se distinguen por su tamano y no por el
/// orden de los tensores: el conversor no garantiza el orden.
///
/// Lanza [FormatException] si las salidas no son una de 21 y otra de 8.
Clasificacion leerSalidasDelClasificador(List<List<double>> salidas) {
  final List<double>? tipos = salidas
      .where((List<double> s) => s.length == ordenTiposClasificador.length)
      .firstOrNull;
  final List<double>? patrones = salidas
      .where((List<double> s) => s.length == ordenPatronesClasificador.length)
      .firstOrNull;
  if (salidas.length != 2 || tipos == null || patrones == null) {
    throw FormatException(
      'El clasificador devolvio salidas de tamano '
      '${salidas.map((List<double> s) => s.length).toList()}; '
      'se esperaban ${ordenTiposClasificador.length} y '
      '${ordenPatronesClasificador.length}',
    );
  }
  final (int tipo, double pTipo) = _mejor(tipos);
  final (int patron, double pPatron) = _mejor(patrones);
  return Clasificacion(
    tipo: ordenTiposClasificador[tipo],
    confianzaTipo: pTipo,
    patron: ordenPatronesClasificador[patron],
    confianzaPatron: pPatron,
  );
}

/// El indice de la clase mas probable y su probabilidad tras softmax.
(int, double) _mejor(List<double> logits) {
  int mejor = 0;
  for (int i = 1; i < logits.length; i++) {
    if (logits[i] > logits[mejor]) mejor = i;
  }
  // Restar el maximo evita desbordar exp() con logits grandes.
  final double maximo = logits[mejor];
  double suma = 0;
  for (final double l in logits) {
    suma += math.exp(l - maximo);
  }
  return (mejor, 1 / suma);
}
