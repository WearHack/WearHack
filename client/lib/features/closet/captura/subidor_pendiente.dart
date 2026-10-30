/// El subidor mientras el Core no recibe prendas (issue #25).
///
/// Responde [SinConexion] en vez de un error: para la cola, no poder subir es
/// lo mismo que no tener red. Asi las prendas ya procesadas esperan con
/// retroceso exponencial, sin gastar intentos ni volverse fallidas, y se suben
/// solas el dia que este el subidor real. La foto original sigue guardada hasta
/// entonces: nada se pierde.
library;

import 'package:wearhack/features/closet/captura/cola_captura.dart';
import 'package:wearhack/platform/captura/contratos.dart';

class SubidorPendiente implements SubidorDePrendas {
  const SubidorPendiente();

  @override
  Future<void> subir(String id, PrendaClasificada prenda) async {
    throw const SinConexion('el Closet aun no recibe prendas (issue #25)');
  }
}
