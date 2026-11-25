/// Cliente de WearHack.
///
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:wearhack/app/pantalla_principal.dart';
import 'package:wearhack/app/tema.dart';
import 'package:wearhack/core/color/categoria_color.dart';
import 'package:wearhack/core/configuracion.dart';
import 'package:wearhack/features/closet/captura/captura_de_prendas.dart';
import 'package:wearhack/features/closet/cliente_closet.dart';
import 'package:wearhack/features/closet/colores/cliente_ajustes_color.dart';
import 'package:wearhack/features/closet/repositorio_closet.dart';
import 'package:wearhack/features/colorimetria/cliente_colorimetria.dart';
import 'package:wearhack/features/colorimetria/conexion_core.dart';
import 'package:wearhack/features/colorimetria/perfil_colorimetria.dart';
import 'package:wearhack/features/colorimetria/repositorio_consentimiento.dart';
import 'package:wearhack/features/colorimetria/repositorio_consentimiento_core.dart';
import 'package:wearhack/features/cuenta/autenticacion.dart';
import 'package:wearhack/features/cuenta/cliente_usuarios.dart';
import 'package:wearhack/features/cuenta/ui/puerta_de_acceso.dart';
import 'package:wearhack/features/outfits/repositorio_clima.dart';
import 'package:wearhack/features/outfits/cliente_outfits.dart';
import 'package:wearhack/features/outfits/repositorio_outfits.dart';
import 'package:wearhack/features/publicidad/repositorio_publicidad.dart';
import 'package:wearhack/mock/repositorio_falso.dart';
import 'package:wearhack/platform/captura.dart';
import 'package:wearhack/platform/captura_pruebas.dart';
import 'package:wearhack/platform/ubicacion.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Sin User Pool en --dart-define la app arranca como antes, sin acceso. Ver
  // infra/cognito/README.md.
  Cuenta? cuenta;

  // Con cuenta, el consentimiento y el analisis de colorimetria van al Core.
  // Sin ella siguen siendo los falsos: no hay a quien atribuirselos.
  final RepositorioFalso datos = RepositorioFalso();
  RepositorioConsentimiento consentimiento = datos;
  ServicioColorimetria? colorimetria;
  FuenteAjustesColor? ajustesColor;
  ClienteCloset? closet;
  RepositorioOutfits outfits = datos;
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
    final ConexionCore conexion = ConexionCore(
      cliente: http.Client(),
      base: Configuracion.coreBase,
      token: autenticacion.tokenDeAcceso,
    );
    closet = ClienteCloset(conexion);
    outfits = ClienteOutfits(conexion, closet);
    consentimiento = RepositorioConsentimientoCore(conexion);
    colorimetria = ClienteColorimetria(conexion);
    ajustesColor = ClienteAjustesColor(
      cliente: http.Client(),
      base: Configuracion.coreBase,
      token: autenticacion.tokenDeAcceso,
    ).ajustes;
  }

  final bool capturaDisponible =
      Configuracion.capturaPrendas && crearGarmentPipeline().disponible;
  CapturaDePrendas? capturaPrendas;
  Future<CapturaDePrendas> Function()? abrirCaptura;
  if (capturaDisponible && closet != null) {
    final ClienteCloset cliente = closet;
    abrirCaptura = () async {
      final String usuario = ClienteCloset.sujeto(
        await cliente.conexion.token(),
      );
      return abrirCapturaDePrendas(
        ajustesColor: ajustesColor,
        usuario: usuario,
        subidor: cliente.subidor(usuario),
      );
    };
  } else if (capturaDisponible) {
    capturaPrendas = await abrirCapturaDePrendas();
    capturaPrendas.cola.arrancar();
  }

  runApp(
    AplicacionWearHack(
      closet: closet ?? datos,
      outfits: outfits,
      clima: closet == null ? datos : null,
      ubicacion: crearServicioUbicacion(),
      publicidad: datos,
      consentimiento: consentimiento,
      colorimetria: colorimetria,
      cuenta: cuenta,
      capturaPrendas: capturaPrendas,
      abrirCaptura: abrirCaptura,
    ),
  );
}

/// Lo necesario para el registro y el inicio de sesion.
class Cuenta {
  const Cuenta({required this.autenticacion, required this.usuarios});

  final Autenticacion autenticacion;
  final ClienteUsuarios usuarios;
}

class AplicacionWearHack extends StatelessWidget {
  const AplicacionWearHack({
    super.key,
    required this.closet,
    required this.outfits,
    required this.clima,
    required this.ubicacion,
    required this.publicidad,
    required this.consentimiento,
    this.colorimetria,
    this.cuenta,
    this.capturaPrendas,
    this.abrirCaptura,
  });

  final RepositorioCloset closet;
  final RepositorioOutfits outfits;
  final RepositorioClima? clima;
  final ServicioUbicacion ubicacion;
  final RepositorioPublicidad publicidad;
  final RepositorioConsentimiento consentimiento;

  /// `null` sin cuenta: la foto se toma pero no se analiza.
  final ServicioColorimetria? colorimetria;

  /// `null` cuando no hay User Pool configurado.
  final Cuenta? cuenta;
  final Future<CapturaDePrendas> Function()? abrirCaptura;

  /// `null` en web o sin `--dart-define=CAPTURA_PRENDAS=true`.
  final CapturaDePrendas? capturaPrendas;

  @override
  Widget build(BuildContext context) {
    final Cuenta? cuenta = this.cuenta;
    Widget principal(CapturaDePrendas? captura) => PantallaPrincipal(
      closet: closet,
      outfits: outfits,
      clima: clima,
      ubicacion: ubicacion,
      publicidad: publicidad,
      consentimiento: consentimiento,
      // Se resuelve con el import condicional: en web no hay ML Kit.
      capturaRostroDisponible: crearFaceCropper().disponible,
      // En web no se llega a usar: el boton de la foto no se ofrece.
      crearCamara: crearCamaraFrontal,
      recortador: crearFaceCropper(),
      diagnostico: (_) => const PantallaEsqueleto(),
      capturaPrendas: captura,
      colorimetria: colorimetria,
    );
    final Future<CapturaDePrendas> Function()? abrir = abrirCaptura;
    final Widget app = abrir == null
        ? principal(capturaPrendas)
        : _CapturaDeSesion(abrir: abrir, principal: principal);
    return MaterialApp(
      title: 'WearHack',
      theme: TemaWearHack.claro,
      darkTheme: TemaWearHack.oscuro,
      home: cuenta == null
          ? app
          : PuertaDeAcceso(
              autenticacion: cuenta.autenticacion,
              usuarios: cuenta.usuarios,
              app: app,
            ),
    );
  }
}

/// La cola autenticada solo existe mientras la puerta muestra la sesión lista.
class _CapturaDeSesion extends StatefulWidget {
  const _CapturaDeSesion({required this.abrir, required this.principal});

  final Future<CapturaDePrendas> Function() abrir;
  final Widget Function(CapturaDePrendas?) principal;

  @override
  State<_CapturaDeSesion> createState() => _CapturaDeSesionState();
}

class _CapturaDeSesionState extends State<_CapturaDeSesion> {
  late Future<CapturaDePrendas> _carga = _abrir();
  CapturaDePrendas? _captura;

  Future<CapturaDePrendas> _abrir() async {
    final CapturaDePrendas captura = await widget.abrir();
    if (mounted) {
      _captura = captura;
      captura.cola.arrancar();
    }
    return captura;
  }

  @override
  void dispose() {
    final CapturaDePrendas? captura = _captura;
    if (captura != null) unawaited(captura.cola.detener());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<CapturaDePrendas>(
    future: _carga,
    builder: (BuildContext context, AsyncSnapshot<CapturaDePrendas> snapshot) {
      if (snapshot.hasError) {
        return Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => setState(() => _carga = _abrir()),
              child: const Text('Reintentar abrir el clóset'),
            ),
          ),
        );
      }
      final CapturaDePrendas? captura = snapshot.data;
      return captura == null
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : widget.principal(captura);
    },
  );
}

/// Que plataforma es y que capacidades on-device resolvio. Se abre desde el
/// icono de informacion de la barra superior.
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
