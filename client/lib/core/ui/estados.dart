/// Lo que muestra una pantalla cuando no tiene datos que pintar.
library;

import 'package:flutter/material.dart';

/// Una lista vacia, explicada. Vacio no es error: un closet nuevo no tiene
/// prendas y una semana puede no tener outfits.
class MensajeVacio extends StatelessWidget {
  const MensajeVacio({super.key, required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icono, size: 48, color: colores.outline),
            const SizedBox(height: 12),
            Text(texto, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// La carga fallo. Con un backend real esto pasa (el gateway devuelve 500 si un
/// servicio esta caido), asi que se puede reintentar sin salir de la pantalla.
class ErrorDeCarga extends StatelessWidget {
  const ErrorDeCarga({super.key, required this.onReintentar});

  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text('No se pudo cargar la información.'),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: onReintentar,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}
