import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wearhack/app/tema.dart';

double _contraste(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final ThemeData tema in <ThemeData>[
    TemaWearHack.claro,
    TemaWearHack.oscuro,
  ]) {
    final ColorScheme c = tema.colorScheme;
    final String modo = c.brightness.name;

    test('$modo: los pares de texto pasan 4.5:1', () {
      final Map<String, (Color, Color)> pares = <String, (Color, Color)>{
        'texto/superficie': (c.onSurface, c.surface),
        'texto/tarjeta': (c.onSurface, c.surfaceContainerLowest),
        'secundario/superficie': (c.onSurfaceVariant, c.surface),
        'secundario/contenedor': (c.onSurfaceVariant, c.surfaceContainer),
        'primario': (c.onPrimary, c.primary),
        'contenedor primario': (c.onPrimaryContainer, c.primaryContainer),
        'secundario': (c.onSecondary, c.secondary),
        'contenedor secundario': (c.onSecondaryContainer, c.secondaryContainer),
        'error': (c.onError, c.error),
        'contenedor error': (c.onErrorContainer, c.errorContainer),
        'primario/superficie': (c.primary, c.surface),
      };
      pares.forEach((String nombre, (Color, Color) par) {
        expect(
          _contraste(par.$1, par.$2),
          greaterThanOrEqualTo(4.5),
          reason: nombre,
        );
      });
    });

    test('$modo: el borde de los campos pasa 3:1', () {
      expect(_contraste(c.outline, c.surface), greaterThanOrEqualTo(3));
      expect(
        _contraste(c.outline, c.surfaceContainerLowest),
        greaterThanOrEqualTo(3),
      );
    });
  }

  test('es Material 3 y claro/oscuro son distintos', () {
    expect(TemaWearHack.claro.useMaterial3, isTrue);
    expect(TemaWearHack.claro.colorScheme.brightness, Brightness.light);
    expect(TemaWearHack.oscuro.colorScheme.brightness, Brightness.dark);
  });
}
