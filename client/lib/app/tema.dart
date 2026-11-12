/// El tema visual de WearHack, claro y oscuro.
///
/// La idea: la interfaz es neutra y fria (un verde petroleo y grises
/// azulados) para que lo unico con color vivo sean las prendas. Las muestras
/// de color del closet y los outfits son lo que debe llamar la atencion, no el
/// chrome. El rosa frambuesa se reserva para lo secundario (etiquetas, chips
/// seleccionados) y nunca para acciones principales.
///
/// Sin fuentes descargadas: se usa la del sistema, para no sumar dependencias
/// ni peticiones de red. La personalidad viene de los pesos y el espaciado.
///
/// Todos los pares texto/fondo pasan 4.5:1 (7:1 en el texto principal). Los
/// bordes de campos pasan 3:1.
library;

import 'package:flutter/material.dart';

abstract final class TemaWearHack {
  static final ThemeData claro = _construir(_esquemaClaro);
  static final ThemeData oscuro = _construir(_esquemaOscuro);

  static const ColorScheme _esquemaClaro = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF1F5560),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFCFE6EA),
    onPrimaryContainer: Color(0xFF0E2F36),
    secondary: Color(0xFFA8325E),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFF6D9E3),
    onSecondaryContainer: Color(0xFF4A1228),
    tertiary: Color(0xFF4C5E66),
    onTertiary: Color(0xFFFFFFFF),
    error: Color(0xFFB3261E),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFF9DEDC),
    onErrorContainer: Color(0xFF410E0B),
    surface: Color(0xFFF5F7F7),
    onSurface: Color(0xFF1A2B33),
    onSurfaceVariant: Color(0xFF4C5E66),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFFFFFFF),
    surfaceContainer: Color(0xFFEBEFEF),
    surfaceContainerHigh: Color(0xFFE3E8E9),
    surfaceContainerHighest: Color(0xFFDCE2E4),
    outline: Color(0xFF6E7F85),
    outlineVariant: Color(0xFFCBD5D8),
    inverseSurface: Color(0xFF1A2B33),
    onInverseSurface: Color(0xFFF5F7F7),
    inversePrimary: Color(0xFF8CC9D3),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  static const ColorScheme _esquemaOscuro = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF8CC9D3),
    onPrimary: Color(0xFF08333B),
    primaryContainer: Color(0xFF1F4A53),
    onPrimaryContainer: Color(0xFFCFE6EA),
    secondary: Color(0xFFF0A9C2),
    onSecondary: Color(0xFF55122D),
    secondaryContainer: Color(0xFF5B1E37),
    onSecondaryContainer: Color(0xFFF6D9E3),
    tertiary: Color(0xFFA6B6BC),
    onTertiary: Color(0xFF11191C),
    error: Color(0xFFF2B8B5),
    onError: Color(0xFF601410),
    errorContainer: Color(0xFF8C1D18),
    onErrorContainer: Color(0xFFF9DEDC),
    surface: Color(0xFF11191C),
    onSurface: Color(0xFFE3EBED),
    onSurfaceVariant: Color(0xFFA6B6BC),
    surfaceContainerLowest: Color(0xFF0C1214),
    surfaceContainerLow: Color(0xFF182226),
    surfaceContainer: Color(0xFF1F2C31),
    surfaceContainerHigh: Color(0xFF26353B),
    surfaceContainerHighest: Color(0xFF2E3F46),
    outline: Color(0xFF6F8087),
    outlineVariant: Color(0xFF34464D),
    inverseSurface: Color(0xFFE3EBED),
    onInverseSurface: Color(0xFF1A2B33),
    inversePrimary: Color(0xFF1F5560),
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
        titleTextStyle: texto.titleLarge?.copyWith(color: c.onSurface),
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
          texto.labelMedium!.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.surfaceContainerLowest,
        indicatorColor: c.primaryContainer,
        selectedLabelTextStyle: texto.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: c.onSurface,
        ),
        unselectedLabelTextStyle: texto.labelMedium?.copyWith(
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
        labelStyle: texto.labelLarge,
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
