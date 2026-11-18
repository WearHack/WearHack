/// El tema visual de WearHack, claro y oscuro.
///
/// Sale del logo: terracota, naranja, ocre y arena sobre un crema calido, con
/// el cafe del nombre para el texto. La interfaz es sobria y las muestras de
/// color de las prendas son lo que mas se ve. El terracota es la accion
/// principal; el ocre, lo secundario (chips seleccionados).
///
/// Sin fuentes descargadas: se usa la del sistema, para no sumar dependencias
/// ni peticiones de red. La personalidad viene de los pesos y el espaciado.
///
/// Todos los pares texto/fondo pasan 4.5:1 y los bordes de campos 3:1; lo
/// comprueba `test/tema_test.dart`.
library;

import 'package:flutter/material.dart';

abstract final class TemaWearHack {
  static final ThemeData claro = _construir(_esquemaClaro);
  static final ThemeData oscuro = _construir(_esquemaOscuro);

  static const ColorScheme _esquemaClaro = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFFA8412B),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFF6D9CC),
    onPrimaryContainer: Color(0xFF4A1D10),
    secondary: Color(0xFF8A5A00),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFF7E3B8),
    onSecondaryContainer: Color(0xFF3E2A00),
    tertiary: Color(0xFF6B2C1E),
    onTertiary: Color(0xFFFFFFFF),
    error: Color(0xFFB3261E),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFF9DEDC),
    onErrorContainer: Color(0xFF410E0B),
    surface: Color(0xFFFAF5EC),
    onSurface: Color(0xFF2E1A14),
    onSurfaceVariant: Color(0xFF6B4F44),
    surfaceContainerLowest: Color(0xFFFFFDF8),
    surfaceContainerLow: Color(0xFFFFFDF8),
    surfaceContainer: Color(0xFFF2EBDF),
    surfaceContainerHigh: Color(0xFFEBE2D4),
    surfaceContainerHighest: Color(0xFFE4D9C9),
    outline: Color(0xFF8A6E62),
    outlineVariant: Color(0xFFE4D6C8),
    inverseSurface: Color(0xFF2E1A14),
    onInverseSurface: Color(0xFFFAF5EC),
    inversePrimary: Color(0xFFF0A08A),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  static const ColorScheme _esquemaOscuro = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFF0A08A),
    onPrimary: Color(0xFF4A1608),
    primaryContainer: Color(0xFF7A3321),
    onPrimaryContainer: Color(0xFFFFDACF),
    secondary: Color(0xFFE8B95A),
    onSecondary: Color(0xFF3E2A00),
    secondaryContainer: Color(0xFF5A4000),
    onSecondaryContainer: Color(0xFFF7E3B8),
    tertiary: Color(0xFFD8B88A),
    onTertiary: Color(0xFF2E1A14),
    error: Color(0xFFF2B8B5),
    onError: Color(0xFF601410),
    errorContainer: Color(0xFF8C1D18),
    onErrorContainer: Color(0xFFF9DEDC),
    surface: Color(0xFF1B1310),
    onSurface: Color(0xFFF2E6DD),
    onSurfaceVariant: Color(0xFFC4AFA3),
    surfaceContainerLowest: Color(0xFF120C0A),
    surfaceContainerLow: Color(0xFF211713),
    surfaceContainer: Color(0xFF251B17),
    surfaceContainerHigh: Color(0xFF2F241F),
    surfaceContainerHighest: Color(0xFF3A2D27),
    outline: Color(0xFF8E7568),
    outlineVariant: Color(0xFF4A3A33),
    inverseSurface: Color(0xFFF2E6DD),
    onInverseSurface: Color(0xFF2E1A14),
    inversePrimary: Color(0xFFA8412B),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  static ThemeData _construir(ColorScheme c) {
    final ThemeData base = ThemeData(
      useMaterial3: true,
      colorScheme: c,
      scaffoldBackgroundColor: c.surface,
    );

    // Titulos mas pesados y apretados, cuerpo sin tocar: la jerarquia sale del
    // peso, no del tamano.
    final TextTheme texto = base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );

    final RoundedRectangleBorder forma = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );

    return base.copyWith(
      textTheme: texto,
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        foregroundColor: c.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 64,
        // Tamano explicito: los estilos de `base.textTheme` todavia no traen
        // el tamano (Flutter se lo pone al arrancar la app), y copiarlos aqui
        // lo dejaba en el tamano del texto base.
        titleTextStyle: texto.headlineSmall?.copyWith(
          fontSize: 24,
          color: c.onSurface,
        ),
        shape: Border(bottom: BorderSide(color: c.outlineVariant)),
      ),
      // Tarjetas planas con borde fino: sin sombra, para que las muestras de
      // color sean lo unico con presencia.
      cardTheme: CardThemeData(
        color: c.surfaceContainerLowest,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: c.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(color: c.outlineVariant, space: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surfaceContainerLowest,
        indicatorColor: c.primaryContainer,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStatePropertyAll<TextStyle>(
          texto.labelMedium!.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.surfaceContainerLowest,
        indicatorColor: c.primaryContainer,
        selectedLabelTextStyle: texto.labelMedium?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: c.onSurface,
        ),
        unselectedLabelTextStyle: texto.labelMedium?.copyWith(
          fontSize: 12,
          color: c.onSurfaceVariant,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: forma,
          minimumSize: const Size(64, 48),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: forma,
          minimumSize: const Size(64, 48),
          side: BorderSide(color: c.outline),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: forma),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        elevation: 1,
        shape: forma,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: c.outlineVariant),
        ),
        selectedColor: c.secondaryContainer,
        labelStyle: texto.labelLarge?.copyWith(fontSize: 14),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.primary, width: 2),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: forma,
      ),
    );
  }
}
