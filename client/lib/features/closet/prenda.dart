/// Una prenda del closet, tal como la guarda el servicio `closet`.
///
/// Refleja el esquema de la coleccion `prendas` (ver
/// `infra/local/mongo/init/01-colecciones.js`).
library;

import 'package:wearhack/core/vocabulario.dart';

class Prenda {
  const Prenda({
    required this.id,
    required this.tipo,
    required this.slot,
    required this.colorLab,
    required this.categoriaColor,
    required this.textura,
    required this.patron,
    required this.formalidad,
    required this.climaApto,
    this.imagenUrl,
    this.tipoCore,
    this.texturaCore,
    this.formalidadCore,
  });

  final String id;
  final TipoPrenda tipo;
  final SlotOutfit slot;

  /// El color medido. Es el que usa el recomendador.
  final ColorLab colorLab;

  /// Redundante con [colorLab] a proposito, igual que en Mongo: sirve para
  /// filtrar y agrupar sin recalcular distancias.
  final CategoriaColor categoriaColor;

  final Textura? textura;
  final Patron patron;
  final Formalidad? formalidad;
  final String? imagenUrl;
  final String? tipoCore;
  final String? texturaCore;
  final String? formalidadCore;

  /// Nunca vacio: el esquema exige al menos un clima.
  final Set<Clima> climaApto;
}
