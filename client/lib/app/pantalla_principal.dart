/// La estructura de la app: closet, outfits y semana.
///
/// En pantallas estrechas (movil) la navegacion va abajo; en anchas (web,
/// tablet) va en un riel a la izquierda, que es donde se busca en escritorio.
library;

import 'package:flutter/material.dart';
import 'package:wearhack/features/closet/repositorio_closet.dart';
import 'package:wearhack/features/closet/ui/pantalla_closet.dart';
import 'package:wearhack/features/outfits/repositorio_outfits.dart';
import 'package:wearhack/features/outfits/ui/pantalla_outfits.dart';
import 'package:wearhack/features/outfits/ui/pantalla_semana.dart';

class PantallaPrincipal extends StatefulWidget {
  const PantallaPrincipal({
    super.key,
    required this.closet,
    required this.outfits,
    this.diagnostico,
  });

  final RepositorioCloset closet;
  final RepositorioOutfits outfits;

  /// La pantalla de diagnostico, si la hay. Llega desde fuera porque vive en
  /// `main.dart`: es la unica que puede abrir el modo de captura de pruebas.
  final WidgetBuilder? diagnostico;

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
  ];

  /// Por encima de este ancho la navegacion pasa a un riel lateral.
  static const double _anchoRiel = 720;

  int _seccion = 0;

  void _ir(int seccion) => setState(() => _seccion = seccion);

  // Cada seccion se construye de nuevo al entrar, y asi recarga. Si se
  // eliminara una prenda en el closet, outfits y semana ya lo reflejan.
  Widget _contenido() => switch (_seccion) {
    0 => PantallaCloset(repositorio: widget.closet),
    1 => PantallaOutfits(repositorio: widget.outfits),
    _ => PantallaSemana(repositorio: widget.outfits),
  };

  @override
  Widget build(BuildContext context) {
    final WidgetBuilder? diagnostico = widget.diagnostico;
    final PreferredSizeWidget barra = AppBar(
      title: Text(_secciones[_seccion].titulo),
      actions: <Widget>[
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

    if (MediaQuery.sizeOf(context).width >= _anchoRiel) {
      return Scaffold(
        appBar: barra,
        body: Row(
          children: <Widget>[
            NavigationRail(
              selectedIndex: _seccion,
              onDestinationSelected: _ir,
              labelType: NavigationRailLabelType.all,
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
