/// El catalogo de las marcas aliadas y las prendas puente.
///
/// Es solo catalogo: no hay inventario ni stock en tiempo real (protocolos,
/// seccion 4). El modulo Publicidad no lee el perfil de colorimetria
/// (politica de datos, seccion 5), asi que nada de aqui lo menciona.
library;

import 'package:wearhack/features/closet/prenda.dart';
import 'package:wearhack/features/outfits/contexto.dart';
import 'package:wearhack/features/outfits/outfit.dart';

/// Por debajo de esto una prenda no se recomienda como puente (respuestas D.28).
const int umbralPrendaPuente = 5;

class MarcaAliada {
  const MarcaAliada({
    required this.id,
    required this.nombre,
    required this.descripcion,
  });

  final String id;
  final String nombre;
  final String descripcion;
}

class ProductoCatalogo {
  const ProductoCatalogo({
    required this.id,
    required this.marca,
    required this.nombre,
    required this.precioPesos,
    required this.prenda,
  });

  final String id;
  final MarcaAliada marca;
  final String nombre;

  /// En pesos colombianos, sin decimales.
  final int precioPesos;

  /// Sus atributos con el mismo vocabulario que una prenda del closet: es lo
  /// que permite combinarla con lo que el usuario ya tiene.
  final Prenda prenda;
}

/// Un producto del catalogo que, con lo que el usuario ya tiene, abre
/// combinaciones nuevas.
class PrendaPuente {
  const PrendaPuente({
    required this.producto,
    required this.combinacionesBuenas,
    required this.ocasionesNuevas,
    required this.ejemplos,
  });

  final ProductoCatalogo producto;

  /// Cuantas combinaciones buenas abre: pasan los filtros duros y cuestan lo
  /// mismo o menos que la mediana de los outfits actuales (D.28).
  final int combinacionesBuenas;

  /// Ocasiones que hoy el usuario no puede cubrir y con esta prenda si. Es el
  /// primer desempate del ranking.
  final List<Ocasion> ocasionesNuevas;

  /// Algunas de esas combinaciones, para enseñarlas.
  final List<Outfit> ejemplos;
}
