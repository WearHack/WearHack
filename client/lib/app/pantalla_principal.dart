/// La estructura de la app: closet, outfits, semana y marcas.
///
/// En pantallas estrechas (movil) la navegacion va abajo; en anchas (web,
/// tablet) va en un riel a la izquierda, que es donde se busca en escritorio.
library;

import 'package:flutter/material.dart';
import 'package:wearhack/app/marca.dart';
import 'package:wearhack/core/ui/movimiento.dart';
import 'package:wearhack/features/closet/captura/captura_de_prendas.dart';
import 'package:wearhack/features/closet/repositorio_closet.dart';
import 'package:wearhack/features/closet/ui/pantalla_captura_prendas.dart';
import 'package:wearhack/features/closet/ui/pantalla_closet.dart';
import 'package:wearhack/features/colorimetria/perfil_colorimetria.dart';
import 'package:wearhack/features/colorimetria/repositorio_consentimiento.dart';
import 'package:wearhack/features/colorimetria/ui/pantalla_colorimetria.dart';
import 'package:wearhack/features/outfits/repositorio_clima.dart';
import 'package:wearhack/features/outfits/repositorio_outfits.dart';
import 'package:wearhack/features/outfits/ui/pantalla_outfits.dart';
import 'package:wearhack/features/outfits/ui/pantalla_semana.dart';
import 'package:wearhack/features/publicidad/repositorio_publicidad.dart';
import 'package:wearhack/features/publicidad/ui/pantalla_marcas.dart';
import 'package:wearhack/platform/captura/camara.dart';
import 'package:wearhack/platform/captura/contratos.dart';
import 'package:wearhack/platform/ubicacion.dart';

class PantallaPrincipal extends StatefulWidget {
  const PantallaPrincipal({
    super.key,
    required this.closet,
    required this.outfits,
    required this.clima,
    required this.ubicacion,
    required this.publicidad,
    required this.consentimiento,
    required this.capturaRostroDisponible,
    this.crearCamara,
    this.recortador,
    this.diagnostico,
    this.capturaPrendas,
    this.colorimetria,
  });

  final RepositorioCloset closet;
  final RepositorioOutfits outfits;
  final RepositorioClima? clima;
  final RepositorioPublicidad publicidad;
  final RepositorioConsentimiento consentimiento;

  /// Si este target puede tomar la foto del rostro (en web no).
  final bool capturaRostroDisponible;

  /// La camara y el recortador de la foto del rostro. Sin ellos el boton de
  /// tomar la foto queda apagado.
  final CamaraDeCaptura Function()? crearCamara;
  final FaceCropper? recortador;
  final ServicioUbicacion ubicacion;

  /// La pantalla de diagnostico, si la hay. Llega desde fuera porque vive en
  /// `main.dart`: es la unica que puede abrir el modo de captura de pruebas.
  final WidgetBuilder? diagnostico;

  /// La captura de prendas en cola (#11), o `null` si no esta disponible: en
  /// web, o sin `--dart-define=CAPTURA_PRENDAS=true`. Con ella, el closet
  /// muestra el boton de agregar prendas.
  final CapturaDePrendas? capturaPrendas;

  /// El analisis de colorimetria contra el Core, o `null` sin cuenta.
  final ServicioColorimetria? colorimetria;

  @override
  State<PantallaPrincipal> createState() => _PantallaPrincipalState();
}

class _Seccion {
  const _Seccion(this.titulo, this.icono, this.iconoActivo);

  final String titulo;
  final IconData icono;
  final IconData iconoActivo;
}

class _PantallaPrincipalState extends State<PantallaPrincipal> {
  static const List<_Seccion> _secciones = <_Seccion>[
    _Seccion('Clóset', Icons.checkroom_outlined, Icons.checkroom),
    _Seccion('Outfits', Icons.style_outlined, Icons.style),
    _Seccion('Semana', Icons.calendar_month_outlined, Icons.calendar_month),
    _Seccion('Marcas', Icons.storefront_outlined, Icons.storefront),
  ];

  /// Por encima de este ancho la navegacion pasa a un riel lateral.
  static const double _anchoRiel = 720;

  int _seccion = 0;

  void _ir(int seccion) => setState(() => _seccion = seccion);

  // Cada seccion se construye de nuevo al entrar, y asi recarga. Si se
  // eliminara una prenda en el closet, outfits y semana ya lo reflejan.
  Widget _contenido() => Aparece(
    // La clave por seccion hace que cada cambio de pestana entre con un
    // fundido, sin dejar la anterior en el arbol mientras se va.
    key: ValueKey<int>(_seccion),
    desliz: 0,
    child: switch (_seccion) {
      0 => PantallaCloset(
        repositorio: widget.closet,
        subidas: widget.capturaPrendas?.cola.subidas,
      ),
      1 => PantallaOutfits(
        repositorio: widget.outfits,
        clima: widget.clima,
        ubicacion: widget.ubicacion,
      ),
      2 => PantallaSemana(repositorio: widget.outfits),
      _ => PantallaMarcas(repositorio: widget.publicidad),
    },
  );

  Widget? _botonAgregarPrendas() {
    final CapturaDePrendas? captura = widget.capturaPrendas;
    if (captura == null || _seccion != 0) return null;
    return FloatingActionButton.extended(
      key: const Key('agregar_prendas'),
      icon: const Icon(Icons.add_a_photo_outlined),
      label: const Text('Agregar prendas'),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PantallaCapturaPrendas(
            cola: captura.cola,
            crearCamara: captura.crearCamara,
            termico: captura.termico,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final WidgetBuilder? diagnostico = widget.diagnostico;
    final bool conRiel = MediaQuery.sizeOf(context).width >= _anchoRiel;
    final PreferredSizeWidget barra = AppBar(
      title: conRiel
          ? Text(_secciones[_seccion].titulo)
          : Row(
              children: <Widget>[
                const MarcaWearHack(alto: 26),
                const SizedBox(width: 12),
                Text(_secciones[_seccion].titulo),
              ],
            ),
      actions: <Widget>[
        IconButton(
          tooltip: 'Tu color',
          icon: const Icon(Icons.palette_outlined),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PantallaColorimetria(
                repositorio: widget.consentimiento,
                capturaDisponible: widget.capturaRostroDisponible,
                crearCamara: widget.crearCamara,
                recortador: widget.recortador,
                servicio: widget.colorimetria,
              ),
            ),
          ),
        ),
        if (diagnostico != null)
          IconButton(
            tooltip: 'Diagnóstico',
            icon: const Icon(Icons.info_outline),
            onPressed: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: diagnostico)),
          ),
      ],
    );

    if (conRiel) {
      return Scaffold(
        appBar: barra,
        floatingActionButton: _botonAgregarPrendas(),
        body: Row(
          children: <Widget>[
            NavigationRail(
              selectedIndex: _seccion,
              onDestinationSelected: _ir,
              labelType: NavigationRailLabelType.all,
              leading: const Padding(
                padding: EdgeInsets.only(top: 14, bottom: 22),
                child: MarcaWearHack(alto: 46),
              ),
              destinations: <NavigationRailDestination>[
                for (final _Seccion s in _secciones)
                  NavigationRailDestination(
                    icon: Icon(s.icono),
                    selectedIcon: Icon(s.iconoActivo),
                    label: Text(s.titulo),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _contenido()),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: barra,
      body: _contenido(),
      floatingActionButton: _botonAgregarPrendas(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _seccion,
        onDestinationSelected: _ir,
        destinations: <NavigationDestination>[
          for (final _Seccion s in _secciones)
            NavigationDestination(
              icon: Icon(s.icono),
              selectedIcon: Icon(s.iconoActivo),
              label: s.titulo,
            ),
        ],
      ),
    );
  }
}
