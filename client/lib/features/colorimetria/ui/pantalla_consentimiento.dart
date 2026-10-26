/// La pantalla de autorizacion, antes de abrir la camara (issue #14).
///
/// Lo que la politica exige de la forma, y por que esta asi:
///
/// - **Sin casilla**: se autoriza con un boton, "Autorizo". Una casilla invita a
///   dejarla premarcada, y eso no es consentimiento.
/// - **Omitir igual de visible que Autorizo**: los dos botones del mismo ancho,
///   uno al lado del otro. Esconder la salida tampoco seria consentimiento.
/// - **Separada de los terminos**: esta pantalla solo habla de la colorimetria.
///
/// Devuelve la decision al cerrarse, o `null` si se sale sin decidir.
library;

import 'package:flutter/material.dart';
import 'package:wearhack/features/colorimetria/consentimiento.dart';
import 'package:wearhack/features/colorimetria/ui/texto_consentimiento.dart';

class PantallaConsentimiento extends StatelessWidget {
  const PantallaConsentimiento({super.key});

  @override
  Widget build(BuildContext context) {
    final TextTheme texto = Theme.of(context).textTheme;
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Autorización')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Text('Tu temporada de color', style: texto.headlineSmall),
              const SizedBox(height: 8),
              Text(introduccionConsentimiento, style: texto.bodyLarge),
              const SizedBox(height: 16),
              for (final SeccionConsentimiento s in seccionesConsentimiento)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(s.icono, color: colores.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(s.titulo, style: texto.titleSmall),
                            const SizedBox(height: 2),
                            Text(s.cuerpo, style: texto.bodyMedium),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              Text(
                'Versión $versionTextoConsentimiento de este texto.',
                style: texto.bodySmall?.copyWith(
                  color: colores.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      Navigator.of(context).pop(DecisionConsentimiento.omitio),
                  child: const Text('Omitir'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () =>
                      Navigator.of(context)
                          .pop(DecisionConsentimiento.autorizo),
                  child: const Text('Autorizo'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
