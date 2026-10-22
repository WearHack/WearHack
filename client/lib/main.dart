/// Cliente de WearHack.
///
/// Las pantallas de closet, outfits y semana estan maquetadas sobre un
/// repositorio falso en memoria (`lib/mock/`). Todavia no hablan con el
/// gateway.
library;

import 'package:flutter/material.dart';
import 'package:wearhack/app/pantalla_principal.dart';
import 'package:wearhack/core/configuracion.dart';
import 'package:wearhack/features/closet/repositorio_closet.dart';
import 'package:wearhack/features/outfits/repositorio_clima.dart';
import 'package:wearhack/features/outfits/repositorio_outfits.dart';
import 'package:wearhack/features/publicidad/repositorio_publicidad.dart';
import 'package:wearhack/mock/repositorio_falso.dart';
import 'package:wearhack/platform/captura.dart';
import 'package:wearhack/platform/captura_pruebas.dart';
import 'package:wearhack/platform/ubicacion.dart';

void main() {
  final RepositorioFalso datos = RepositorioFalso();
  runApp(
    AplicacionWearHack(
      closet: datos,
      outfits: datos,
      clima: datos,
      ubicacion: crearServicioUbicacion(),
      publicidad: datos,
    ),
  );
}

class AplicacionWearHack extends StatelessWidget {
  const AplicacionWearHack({
    super.key,
    required this.closet,
    required this.outfits,
    required this.clima,
    required this.ubicacion,
    required this.publicidad,
  });

  final RepositorioCloset closet;
  final RepositorioOutfits outfits;
  final RepositorioClima clima;
  final ServicioUbicacion ubicacion;
  final RepositorioPublicidad publicidad;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WearHack',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: PantallaPrincipal(
        closet: closet,
        outfits: outfits,
        clima: clima,
        ubicacion: ubicacion,
        publicidad: publicidad,
        diagnostico: (_) => const PantallaEsqueleto(),
      ),
    );
  }
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
