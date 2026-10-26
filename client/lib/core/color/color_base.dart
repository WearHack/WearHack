/// El color base de una prenda (issue #13): el color que la define, sacado de
/// los pixeles que la forman.
///
/// Entra la imagen de la prenda ya sin fondo (RGBA, el fondo transparente) y sale
/// un color en Lab. Pasos:
///
/// 1. Se toman solo los pixeles opacos, y si son muchos se muestrean: el color de
///    una prenda no necesita 12 millones de pixeles.
/// 2. Se pasan a Lab con la **misma cadena** que el resto del cliente
///    (`perfilALab`), no con una formula aparte.
/// 3. Se descartan las **sombras** y los **brillos**: los pixeles mas oscuros y
///    los mas claros por luminosidad. Un pliegue o un reflejo de luz no son el
///    color de la tela.
/// 4. Con lo que queda, el color dominante: el centroide del grupo mas grande
///    (k-means) o el color mas frecuente (moda).
///
/// **Ningun parametro de dominio esta definido todavia**: ni el metodo, ni `k`,
/// ni cuanto se descarta de sombras y brillos. Como el recorte facial, no traen
/// valor por defecto y se pasan al compilar. Ver [ConfiguracionColorBase].
///
/// Solo Dart, sin plugins: corre igual en el telefono y en las pruebas.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:wearhack/core/color/conversion.dart';
import 'package:wearhack/core/color/perfil_icc.dart';
import 'package:wearhack/core/vocabulario.dart';

enum MetodoColorBase {
  /// El centroide del grupo mas grande de `k` grupos.
  kmeans,

  /// El color mas frecuente, agrupando colores casi iguales en cubos de Lab.
  moda,
}

/// La configuracion falta o tiene un valor invalido.
class ConfiguracionColorBaseInvalida implements Exception {
  const ConfiguracionColorBaseInvalida(this.problemas);

  /// Una frase por problema, con el nombre del `--dart-define` afectado.
  final List<String> problemas;

  @override
  String toString() =>
      'ConfiguracionColorBaseInvalida: ${problemas.join('; ')}. '
      'Se pasan con --dart-define=NOMBRE=valor al compilar.';
}

/// Parametros del color base.
///
///   flutter run \
///     --dart-define=COLOR_METODO=kmeans \
///     --dart-define=COLOR_K=3 \
///     --dart-define=COLOR_SOMBRAS_PCT=10 \
///     --dart-define=COLOR_BRILLOS_PCT=5
///
/// (esos numeros son solo un ejemplo de formato, no una recomendacion.)
///
/// El metodo, `k` (solo con k-means) y los dos porcentajes son obligatorios.
/// Los demas son de rendimiento y llevan un valor por defecto.
class ConfiguracionColorBase {
  const ConfiguracionColorBase({
    required this.metodo,
    this.k,
    required this.sombrasPct,
    required this.brillosPct,
    this.alfaMinimo = 128,
    this.maxPixeles = 20000,
    this.iteracionesMax = 25,
    this.cuantoModa = 4,
    this.semilla = 1,
  }) : assert(
         metodo != MetodoColorBase.kmeans || (k != null && k >= 1),
         'k-means necesita k >= 1',
       ),
       assert(sombrasPct >= 0 && brillosPct >= 0),
       assert(sombrasPct + brillosPct < 100),
       assert(alfaMinimo >= 0 && alfaMinimo <= 255),
       assert(maxPixeles > 0 && iteracionesMax > 0),
       assert(cuantoModa >= 0.5),
       assert(semilla >= 1 && semilla < 2147483647);

  final MetodoColorBase metodo;

  /// Numero de grupos. Solo con [MetodoColorBase.kmeans].
  final int? k;

  /// Que porcentaje de los pixeles mas oscuros se descarta, de 0 a 100.
  final double sombrasPct;

  /// Que porcentaje de los pixeles mas claros se descarta, de 0 a 100.
  final double brillosPct;

  /// Un pixel con menos opacidad que esto se toma por fondo, de 0 a 255.
  final int alfaMinimo;

  /// Tope de pixeles que se analizan. Es de rendimiento, no de dominio.
  final int maxPixeles;

  final int iteracionesMax;

  /// Ancho de cada cubo de la moda, en unidades de Lab. Minimo 0,5.
  final double cuantoModa;

  /// Semilla del azar de k-means. Fija, para que el mismo dato de el mismo color.
  final int semilla;

  /// Lee la configuracion de los `--dart-define` del build.
  factory ConfiguracionColorBase.desdeEntorno() =>
      ConfiguracionColorBase.desdeTextos(const <String, String>{
        'COLOR_METODO': String.fromEnvironment('COLOR_METODO'),
        'COLOR_K': String.fromEnvironment('COLOR_K'),
        'COLOR_SOMBRAS_PCT': String.fromEnvironment('COLOR_SOMBRAS_PCT'),
        'COLOR_BRILLOS_PCT': String.fromEnvironment('COLOR_BRILLOS_PCT'),
      });

  /// Construye la configuracion desde textos. Separado de [desdeEntorno] para
  /// poder probarlo: `String.fromEnvironment` solo admite constantes.
  ///
  /// Un texto vacio cuenta como ausente.
  factory ConfiguracionColorBase.desdeTextos(Map<String, String> valores) {
    final List<String> problemas = <String>[];
    String texto(String nombre) => (valores[nombre] ?? '').trim();

    MetodoColorBase? metodo;
    final String metodoTexto = texto('COLOR_METODO').toLowerCase();
    if (metodoTexto.isEmpty) {
      problemas.add('falta COLOR_METODO (kmeans o moda)');
    } else {
      metodo = MetodoColorBase.values
          .where((MetodoColorBase m) => m.name == metodoTexto)
          .firstOrNull;
      if (metodo == null) {
        problemas.add('COLOR_METODO="$metodoTexto" no es kmeans ni moda');
      }
    }

    int? k;
    final String kTexto = texto('COLOR_K');
    if (kTexto.isEmpty) {
      if (metodo == MetodoColorBase.kmeans) problemas.add('falta COLOR_K');
    } else {
      k = int.tryParse(kTexto);
      if (k == null || k < 1) {
        problemas.add('COLOR_K="$kTexto" no es un entero mayor o igual a 1');
        k = null;
      }
    }

    double? porcentaje(String nombre) {
      final String t = texto(nombre);
      if (t.isEmpty) {
        problemas.add('falta $nombre');
        return null;
      }
      final double? v = double.tryParse(t);
      if (v == null || !v.isFinite || v < 0 || v >= 100) {
        problemas.add('$nombre="$t" no es un numero de 0 a menos de 100');
        return null;
      }
      return v;
    }

    final double? sombras = porcentaje('COLOR_SOMBRAS_PCT');
    final double? brillos = porcentaje('COLOR_BRILLOS_PCT');
    if (sombras != null && brillos != null && sombras + brillos >= 100) {
      problemas.add(
        'COLOR_SOMBRAS_PCT y COLOR_BRILLOS_PCT suman $sombras + $brillos: '
        'no puede quedar nada',
      );
    }

    if (problemas.isNotEmpty) throw ConfiguracionColorBaseInvalida(problemas);

    return ConfiguracionColorBase(
      metodo: metodo!,
      k: k,
      sombrasPct: sombras!,
      brillosPct: brillos!,
    );
  }
}

class ResultadoColorBase {
  const ResultadoColorBase({
    required this.color,
    required this.proporcion,
    required this.pixelesOpacos,
    required this.pixelesAnalizados,
    required this.descartadosSombras,
    required this.descartadosBrillos,
  });

  final ColorLab color;

  /// Que parte de los pixeles conservados forma el grupo dominante, de 0 a 1.
  /// Cerca de 1, la prenda es de un color; mucho menos, hay varios.
  final double proporcion;

  /// Pixeles opacos de la imagen, antes de muestrear.
  final int pixelesOpacos;

  /// Pixeles que entraron al calculo, ya muestreados y sin sombras ni brillos.
  final int pixelesAnalizados;

  /// Cuantos pixeles de la muestra se descartaron por oscuros y por claros.
  final int descartadosSombras;
  final int descartadosBrillos;
}

/// Calcula el color base, o `null` si la imagen no tiene ningun pixel opaco.
///
/// [rgba] son 4 bytes por pixel, sRGB, con la opacidad sin premultiplicar.
ResultadoColorBase? calcularColorBase({
  required Uint8List rgba,
  required int ancho,
  required int alto,
  required ConfiguracionColorBase configuracion,
}) {
  if (ancho <= 0 || alto <= 0 || rgba.length != ancho * alto * 4) {
    throw ArgumentError(
      'rgba debe tener ancho*alto*4 bytes: son ${rgba.length} bytes para una '
      'imagen de ${ancho}x$alto',
    );
  }

  final int total = ancho * alto;
  int opacos = 0;
  for (int i = 0; i < total; i++) {
    if (rgba[i * 4 + 3] >= configuracion.alfaMinimo) opacos++;
  }
  if (opacos == 0) return null;

  // Muestreo regular de los opacos: cada `paso`-esimo.
  final int paso =
      (opacos + configuracion.maxPixeles - 1) ~/ configuracion.maxPixeles;
  final int muestra = (opacos + paso - 1) ~/ paso;
  final Float64List l = Float64List(muestra);
  final Float64List a = Float64List(muestra);
  final Float64List b = Float64List(muestra);
  int vistos = 0;
  int n = 0;
  for (int i = 0; i < total; i++) {
    final int o = i * 4;
    if (rgba[o + 3] < configuracion.alfaMinimo) continue;
    if (vistos % paso == 0) {
      final ColorLab c = perfilALab(
        PerfilRgb.srgb,
        rgba[o],
        rgba[o + 1],
        rgba[o + 2],
      );
      l[n] = c.l;
      a[n] = c.a;
      b[n] = c.b;
      n++;
    }
    vistos++;
  }

  // Sombras y brillos: por rango de luminosidad, no por un valor fijo. Asi una
  // prenda blanca o negra no se queda sin pixeles.
  final List<int> orden = List<int>.generate(n, (int i) => i)
    ..sort((int x, int y) => l[x].compareTo(l[y]));
  final int sombras = (n * configuracion.sombrasPct / 100).floor();
  final int brillos = (n * configuracion.brillosPct / 100).floor();
  final int m = n - sombras - brillos;

  final Float64List kl = Float64List(m);
  final Float64List ka = Float64List(m);
  final Float64List kb = Float64List(m);
  for (int j = 0; j < m; j++) {
    final int origen = orden[sombras + j];
    kl[j] = l[origen];
    ka[j] = a[origen];
    kb[j] = b[origen];
  }

  final _Dominante dominante = switch (configuracion.metodo) {
    MetodoColorBase.kmeans => _dominanteKmeans(
      kl,
      ka,
      kb,
      configuracion.k!,
      configuracion.iteracionesMax,
      configuracion.semilla,
    ),
    MetodoColorBase.moda => _dominanteModa(
      kl,
      ka,
      kb,
      configuracion.cuantoModa,
    ),
  };

  return ResultadoColorBase(
    color: dominante.color,
    proporcion: dominante.tamano / m,
    pixelesOpacos: opacos,
    pixelesAnalizados: m,
    descartadosSombras: sombras,
    descartadosBrillos: brillos,
  );
}

class _Dominante {
  const _Dominante(this.color, this.tamano);
  final ColorLab color;
  final int tamano;
}

double _distancia2(
  double l1,
  double a1,
  double b1,
  double l2,
  double a2,
  double b2,
) {
  final double dl = l1 - l2;
  final double da = a1 - a2;
  final double db = b1 - b2;
  return dl * dl + da * da + db * db;
}

/// Park-Miller. Un generador propio y no `dart:math`, porque `Random(semilla)`
/// no promete dar la misma secuencia en todas las plataformas ni versiones, y
/// aqui el mismo dato tiene que dar siempre el mismo color. El producto cabe en
/// 53 bits, asi que da igual en la VM y en la web.
class _Aleatorio {
  _Aleatorio(this._estado);

  int _estado;

  int _siguiente() {
    _estado = (_estado * 48271) % 2147483647;
    return _estado;
  }

  int entero(int max) => _siguiente() % max;

  double decimal() => _siguiente() / 2147483647;
}

/// k-means con inicializacion k-means++. Devuelve el centroide del grupo mas
/// grande.
_Dominante _dominanteKmeans(
  Float64List l,
  Float64List a,
  Float64List b,
  int k,
  int iteraciones,
  int semilla,
) {
  final int m = l.length;
  final int kk = k < m ? k : m;
  final Float64List cl = Float64List(kk);
  final Float64List ca = Float64List(kk);
  final Float64List cb = Float64List(kk);
  final _Aleatorio azar = _Aleatorio(semilla);

  final int primero = azar.entero(m);
  cl[0] = l[primero];
  ca[0] = a[primero];
  cb[0] = b[primero];
  final Float64List dist = Float64List(m)..fillRange(0, m, double.infinity);
  for (int c = 1; c < kk; c++) {
    double suma = 0;
    for (int i = 0; i < m; i++) {
      final double d = _distancia2(
        l[i],
        a[i],
        b[i],
        cl[c - 1],
        ca[c - 1],
        cb[c - 1],
      );
      if (d < dist[i]) dist[i] = d;
      suma += dist[i];
    }
    int elegido = 0;
    if (suma > 0) {
      final double objetivo = azar.decimal() * suma;
      double acumulado = 0;
      elegido = m - 1;
      for (int i = 0; i < m; i++) {
        acumulado += dist[i];
        if (acumulado >= objetivo) {
          elegido = i;
          break;
        }
      }
    }
    cl[c] = l[elegido];
    ca[c] = a[elegido];
    cb[c] = b[elegido];
  }

  final Int32List asignado = Int32List(m)..fillRange(0, m, -1);
  final Int32List cuenta = Int32List(kk);
  for (int it = 0; it < iteraciones; it++) {
    bool cambio = false;
    for (int i = 0; i < m; i++) {
      int mejor = 0;
      double mejorDist = double.infinity;
      for (int c = 0; c < kk; c++) {
        final double d = _distancia2(l[i], a[i], b[i], cl[c], ca[c], cb[c]);
        if (d < mejorDist) {
          mejorDist = d;
          mejor = c;
        }
      }
      if (asignado[i] != mejor) {
        asignado[i] = mejor;
        cambio = true;
      }
    }

    final Float64List sl = Float64List(kk);
    final Float64List sa = Float64List(kk);
    final Float64List sb = Float64List(kk);
    cuenta.fillRange(0, kk, 0);
    for (int i = 0; i < m; i++) {
      final int c = asignado[i];
      sl[c] += l[i];
      sa[c] += a[i];
      sb[c] += b[i];
      cuenta[c]++;
    }
    // Un grupo que se quedo vacio conserva su centroide anterior.
    for (int c = 0; c < kk; c++) {
      if (cuenta[c] > 0) {
        cl[c] = sl[c] / cuenta[c];
        ca[c] = sa[c] / cuenta[c];
        cb[c] = sb[c] / cuenta[c];
      }
    }
    if (!cambio) break;
  }

  int dominante = 0;
  for (int c = 1; c < kk; c++) {
    if (cuenta[c] > cuenta[dominante]) dominante = c;
  }
  return _Dominante(
    ColorLab(l: cl[dominante], a: ca[dominante], b: cb[dominante]),
    cuenta[dominante],
  );
}

class _Cubo {
  int cuenta = 0;
  double l = 0;
  double a = 0;
  double b = 0;
}

/// El cubo de Lab con mas pixeles; el color es la media de lo que cayo ahi.
_Dominante _dominanteModa(
  Float64List l,
  Float64List a,
  Float64List b,
  double cuanto,
) {
  final Map<int, _Cubo> cubos = <int, _Cubo>{};
  for (int i = 0; i < l.length; i++) {
    // Cada coordenada en 10 bits: con un cubo de 0,5 o mas, Lab cabe de sobra.
    final int cl = (l[i] / cuanto).round() + 512;
    final int ca = (a[i] / cuanto).round() + 512;
    final int cb = (b[i] / cuanto).round() + 512;
    cubos.putIfAbsent((cl << 20) | (ca << 10) | cb, _Cubo.new)
      ..cuenta += 1
      ..l += l[i]
      ..a += a[i]
      ..b += b[i];
  }

  // El mas poblado; en un empate, el de menor clave, para que sea repetible.
  int? mejorClave;
  for (final MapEntry<int, _Cubo> e in cubos.entries) {
    final _Cubo? actual = mejorClave == null ? null : cubos[mejorClave];
    if (actual == null ||
        e.value.cuenta > actual.cuenta ||
        (e.value.cuenta == actual.cuenta && e.key < mejorClave!)) {
      mejorClave = e.key;
    }
  }
  final _Cubo ganador = cubos[mejorClave]!;
  return _Dominante(
    ColorLab(
      l: ganador.l / ganador.cuenta,
      a: ganador.a / ganador.cuenta,
      b: ganador.b / ganador.cuenta,
    ),
    ganador.cuenta,
  );
}

/// Distancia entre dos colores Lab (CIE76), la que se usa en las pruebas y en la
/// comparacion de colores del cliente.
double distanciaLab(ColorLab x, ColorLab y) =>
    math.sqrt(_distancia2(x.l, x.a, x.b, y.l, y.a, y.b));
