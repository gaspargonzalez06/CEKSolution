import 'package:flutter/material.dart';

/// Tema visual de la aplicación (colores, tarjetas, formularios, tipografía).
///
/// Un único punto de verdad para claro y oscuro: toda la app (pantallas,
/// tarjetas, formularios, tablas) toma su aspecto de aquí, de modo que el modo
/// claro y el oscuro queden siempre consistentes.
class AppTheme {
  static const Color semilla = Color(0xFF0B6E4F);
  static const Color verde = Color(0xFF12B886);
  static const Color azul = Color(0xFF315C8A);
  static const Color ambar = Color(0xFFF0A020);
  static const Color rojo = Color(0xFFD84A43);
  static const Color morado = Color(0xFF7C4DFF);

  /// Paleta de acentos usada en gráficas y KPIs.
  static const List<Color> acentos = [azul, verde, ambar, morado, rojo];

  static ThemeData claro() => _construir(Brightness.light);

  static ThemeData oscuro() => _construir(Brightness.dark);

  static ThemeData _construir(Brightness brillo) {
    final oscuro = brillo == Brightness.dark;

    var esquema = ColorScheme.fromSeed(seedColor: semilla, brightness: brillo);
    if (oscuro) {
      esquema = esquema.copyWith(
        surface: const Color(0xFF151A21),
        onSurface: const Color(0xFFE7ECF3),
        surfaceContainerLowest: const Color(0xFF0E1218),
        surfaceContainerHighest: const Color(0xFF232B36),
        onSurfaceVariant: const Color(0xFFAEB8C6),
        outline: const Color(0xFF7C8798),
        outlineVariant: const Color(0xFF2A323D),
        primary: const Color(0xFF4FD1A5),
        onPrimary: const Color(0xFF00251A),
        primaryContainer: const Color(0xFF0E4A38),
        onPrimaryContainer: const Color(0xFFB9F2DD),
      );
    } else {
      esquema = esquema.copyWith(
        surface: Colors.white,
        surfaceContainerHighest: const Color(0xFFEDF1F6),
        onSurfaceVariant: const Color(0xFF5A6672),
        outlineVariant: const Color(0xFFE4E9EF),
      );
    }

    final fondo = oscuro ? const Color(0xFF0D1117) : const Color(0xFFF4F7FB);
    final superficie = esquema.surface;
    final rellenoCampo = oscuro ? const Color(0xFF1B222C) : Colors.white;
    final borde = esquema.outlineVariant;
    final bordeFuerte = oscuro ? const Color(0xFF39424F) : const Color(0xFFC9D3DE);

    InputDecorationTheme campo() => InputDecorationTheme(
          isDense: true,
          filled: true,
          fillColor: rellenoCampo,
          labelStyle: TextStyle(color: esquema.onSurfaceVariant),
          floatingLabelStyle: TextStyle(
              color: esquema.primary, fontWeight: FontWeight.w600),
          hintStyle: TextStyle(color: esquema.outline),
          prefixIconColor: esquema.onSurfaceVariant,
          suffixIconColor: esquema.onSurfaceVariant,
          helperStyle: TextStyle(color: esquema.outline),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: bordeFuerte),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: borde),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: esquema.primary, width: 1.8),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: esquema.error),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: esquema.error, width: 1.8),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        );

    final radio = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));

    return ThemeData(
      useMaterial3: true,
      brightness: brillo,
      colorScheme: esquema,
      scaffoldBackgroundColor: fondo,
      canvasColor: fondo,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: superficie,
        surfaceTintColor: Colors.transparent,
        foregroundColor: esquema.onSurface,
        titleTextStyle: TextStyle(
            color: esquema.onSurface, fontSize: 18, fontWeight: FontWeight.w700),
      ),
      cardTheme: CardThemeData(
        elevation: oscuro ? 0 : 1,
        shadowColor: Colors.black.withValues(alpha: 0.05),
        margin: EdgeInsets.zero,
        color: superficie,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: borde),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: superficie,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      ),
      inputDecorationTheme: campo(),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.1),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          side: BorderSide(color: bordeFuerte),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: BorderSide(color: borde),
        backgroundColor: superficie,
        labelStyle: TextStyle(color: esquema.onSurface, fontWeight: FontWeight.w600),
      ),
      dividerTheme: DividerThemeData(color: borde, thickness: 1, space: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: oscuro ? const Color(0xFF2A3340) : const Color(0xFF1F2933),
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        iconColor: esquema.onSurfaceVariant,
      ),
      expansionTileTheme: ExpansionTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        iconColor: esquema.primary,
        collapsedIconColor: esquema.onSurfaceVariant,
        textColor: esquema.onSurface,
        collapsedTextColor: esquema.onSurface,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          ),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: superficie,
        indicatorColor: esquema.primary.withValues(alpha: oscuro ? 0.22 : 0.12),
        selectedIconTheme: IconThemeData(color: esquema.primary),
        selectedLabelTextStyle:
            TextStyle(color: esquema.primary, fontWeight: FontWeight.w700),
        unselectedIconTheme: IconThemeData(color: esquema.onSurfaceVariant),
        unselectedLabelTextStyle: TextStyle(color: esquema.onSurfaceVariant),
        useIndicator: true,
      ),
      drawerTheme: DrawerThemeData(backgroundColor: superficie),
      popupMenuTheme: PopupMenuThemeData(
        color: superficie,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(superficie),
          shape: WidgetStatePropertyAll(radio),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: oscuro ? const Color(0xFF2B3441) : const Color(0xFF313B47),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: esquema.primary),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? esquema.onPrimary : null),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? esquema.primary : null),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: superficie,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(esquema.outline.withValues(alpha: 0.5)),
        radius: const Radius.circular(8),
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(letterSpacing: -0.3),
        titleMedium: TextStyle(letterSpacing: -0.2),
      ),
    );
  }
}
