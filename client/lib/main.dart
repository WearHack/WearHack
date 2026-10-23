/// Cliente de WearHack.
///
/// Esqueleto. Arranca y muestra de que plataforma se trata y si la captura
/// on-device esta disponible. Sin UI real.
library;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:wearhack/core/configuracion.dart';
import 'package:wearhack/features/cuenta/autenticacion.dart';
import 'package:wearhack/features/cuenta/cliente_usuarios.dart';
import 'package:wearhack/features/cuenta/ui/puerta_de_acceso.dart';
import 'package:wearhack/platform/captura.dart';
import 'package:wearhack/platform/captura_pruebas.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Sin User Pool en --dart-define la app arranca como antes, sin acceso. Ver
  // infra/cognito/README.md.
  Cuenta? cuenta;
  if (Configuracion.cognitoConfigurado) {
    final Autenticacion autenticacion = await AutenticacionAmplify.configurar(
      region: Configuracion.cognitoRegion,
      userPoolId: Configuracion.cognitoUserPoolId,
      clientId: Configuracion.cognitoClientId,
      dominio: Configuracion.cognitoDominio,
    );
    cuenta = Cuenta(
      autenticacion: autenticacion,
      usuarios: ClienteUsuarios(
        cliente: http.Client(),
        base: Configuracion.coreBase,
        token: autenticacion.tokenDeAcceso,
      ),
    );
  }
  runApp(AplicacionWearHack(cuenta: cuenta));
}

/// Lo necesario para el registro y el inicio de sesion.
class Cuenta {
  const Cuenta({required this.autenticacion, required this.usuarios});

  final Autenticacion autenticacion;
  final ClienteUsuarios usuarios;
}

class AplicacionWearHack extends StatelessWidget {
  const AplicacionWearHack({super.key, this.cuenta});

  /// `null` cuando no hay User Pool configurado.
  final Cuenta? cuenta;

  @override
  Widget build(BuildContext context) {
    final Cuenta? cuenta = this.cuenta;
    return MaterialApp(
      title: 'WearHack',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: cuenta == null
          ? const PantallaEsqueleto()
          : PuertaDeAcceso(
              autenticacion: cuenta.autenticacion,
              usuarios: cuenta.usuarios,
              app: const PantallaEsqueleto(),
            ),
    );
  }
}

class PantallaEsqueleto extends StatelessWidget {
  const PantallaEsqueleto({super.key});

  @override
  Widget build(BuildContext context) {
    final pipeline = crearGarmentPipeline();
    final recortador = crearFaceCropper();

    return Scaffold(
      appBar: AppBar(title: const Text('WearHack')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('Esqueleto'),
            const SizedBox(height: 12),
            // version y apiBase son constantes de compilacion, asi que
            // estos dos si pueden ser const. Los de mas abajo no:
            // dependen de que implementacion resolvio el import
            // condicional, y eso se sabe en tiempo de ejecucion.
            const Text('version ${Configuracion.version}'),
            const Text('api ${Configuracion.apiBase}'),
            const SizedBox(height: 12),
            // Lo unico que esta pantalla demuestra: que el import condicional
            // resolvio a la implementacion correcta para este target.
            Text('clasificacion on-device: ${pipeline.disponible}'),
            Text('recorte de rostro: ${recortador.disponible}'),
            // Solo en builds internas (--dart-define=CAPTURA_PRUEBAS=true). La
            // constante se resuelve al compilar, asi que sin el flag este
            // boton y todo lo que abre desaparecen del programa.
            if (Configuracion.capturaPruebas) ...<Widget>[
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => abrirCapturaPruebas(context),
                child: const Text('Captura de pruebas (build interna)'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
