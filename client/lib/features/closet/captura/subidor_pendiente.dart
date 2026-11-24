/// El subidor para las builds de captura sin una sesión de Cognito.
///
/// Responde [SinConexion] en vez de un error: para la cola, no poder subir es
/// lo mismo que no tener red. Asi las prendas ya procesadas esperan con
/// retroceso exponencial, sin gastar intentos ni volverse fallidas, y se guardan
/// en la cola local. Solo las capturas hechas con sesión se asocian a una cuenta.
library;

import 'package:wearhack/features/closet/captura/cola_captura.dart';
import 'package:wearhack/platform/captura/contratos.dart';

class SubidorPendiente implements SubidorDePrendas {
  const SubidorPendiente();

  @override
  Future<void> subir(String id, PrendaClasificada prenda) async {
    throw const SinConexion('La captura se abrió sin una cuenta');
  }
}
