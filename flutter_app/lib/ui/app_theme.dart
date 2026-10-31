import 'package:flutter/material.dart';

/// App themes. Light is hand-tuned for photo backgrounds (opaque cards,
/// strong contrast) — M3 `fromSeed` alone looked foggy/washed-out.
class AppTheme {
  // —— Light brand ——
  static const _lightPrimary = Color(0xFF1A56DB);
  static const _lightOnPrimary = Color(0xFFFFFFFF);
  static const _lightPrimaryContainer = Color(0xFFDCE8FF);
  static const _lightOnPrimaryContainer = Color(0xFF0A2348);

  static const _lightSecondary = Color(0xFF3D5A80);
  static const _lightOnSecondary = Color(0xFFFFFFFF);
  static const _lightSecondaryContainer = Color(0xFFD9E4F2);
  static const _lightOnSecondaryContainer = Color(0xFF1B2A3D);

  static const _lightError = Color(0xFFC62828);
  static const _lightOnError = Color(0xFFFFFFFF);
  static const _lightErrorContainer = Color(0xFFFFDAD6);
  static const _lightOnErrorContainer = Color(0xFF410002);

  /// Cool paper — not muddy gray.
  static const _lightSurface = Color(0xFFF5F7FB);
  static const _lightOnSurface = Color(0xFF10141C);
  static const _lightOnSurfaceVariant = Color(0xFF3E4656);
  static const _lightSurfaceContainerLowest = Color(0xFFFFFFFF);
  static const _lightSurfaceContainerLow = Color(0xFFEEF1F7);
  static const _lightSurfaceContainer = Color(0xFFE8ECF4);
  static const _lightSurfaceContainerHigh = Color(0xFFE1E6F0);
  static const _lightSurfaceContainerHighest = Color(0xFFFFFFFF);
  static const _lightOutline = Color(0xFF5C6578);
  static const _lightOutlineVariant = Color(0xFFC5CCD9);
  static const _lightInverseSurface = Color(0xFF1C222E);
  static const _lightOnInverseSurface = Color(0xFFF0F3F8);
  static const _lightInversePrimary = Color(0xFFAEC6FF);
  static const _lightScrim = Color(0xFF000000);
  static const _lightShadow = Color(0xFF000000);

  static ColorScheme get _lightScheme => const ColorScheme(
        brightness: Brightness.light,
        primary: _lightPrimary,
        onPrimary: _lightOnPrimary,
        primaryContainer: _lightPrimaryContainer,
        onPrimaryContainer: _lightOnPrimaryContainer,
        secondary: _lightSecondary,
        onSecondary: _lightOnSecondary,
        secondaryContainer: _lightSecondaryContainer,
        onSecondaryContainer: _lightOnSecondaryContainer,
        tertiary: Color(0xFF006C51),
        onTertiary: Color(0xFFFFFFFF),
        tertiaryContainer: Color(0xFF89F8D0),
        onTertiaryContainer: Color(0xFF002116),
        error: _lightError,
        onError: _lightOnError,
        errorContainer: _lightErrorContainer,
        onErrorContainer: _lightOnErrorContainer,
        surface: _lightSurface,
        onSurface: _lightOnSurface,
        onSurfaceVariant: _lightOnSurfaceVariant,
        surfaceContainerLowest: _lightSurfaceContainerLowest,
        surfaceContainerLow: _lightSurfaceContainerLow,
        surfaceContainer: _lightSurfaceContainer,
        surfaceContainerHigh: _lightSurfaceContainerHigh,
        surfaceContainerHighest: _lightSurfaceContainerHighest,
        outline: _lightOutline,
        outlineVariant: _lightOutlineVariant,
        shadow: _lightShadow,
        scrim: _lightScrim,
        inverseSurface: _lightInverseSurface,
        onInverseSurface: _lightOnInverseSurface,
        inversePrimary: _lightInversePrimary,
        surfaceTint: _lightPrimary,
      );

  static ThemeData get light {
    final scheme = _lightScheme;
    final baseText = Typography.material2021(platform: TargetPlatform.windows)
        .black
        .apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      dividerColor: scheme.outlineVariant,
      textTheme: baseText.copyWith(
        titleLarge: baseText.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: baseText.titleMedium?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        titleSmall: baseText.titleSmall?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: baseText.bodyLarge?.copyWith(color: scheme.onSurface),
        bodyMedium: baseText.bodyMedium?.copyWith(color: scheme.onSurface),
        bodySmall: baseText.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        labelLarge: baseText.labelLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: scheme.surfaceContainerLowest.withValues(alpha: 0.94),
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: Colors.transparent,
        shadowColor: scheme.shadow.withValues(alpha: 0.08),
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface, size: 24),
        actionsIconTheme: IconThemeData(color: scheme.onSurface, size: 24),
      ),
      cardTheme: CardThemeData(
        // Solid white — no translucent fog over the photo.
        color: scheme.surfaceContainerLowest,
        elevation: 1.5,
        shadowColor: scheme.shadow.withValues(alpha: 0.14),
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 13.5,
          height: 1.25,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        behavior: SnackBarBehavior.floating,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 3,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.65)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: scheme.primary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.75)),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.7),
        thickness: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        selectedColor: scheme.primaryContainer,
        labelStyle: TextStyle(color: scheme.onSurface),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          foregroundColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.selected)) {
              return scheme.onPrimaryContainer;
            }
            return scheme.onSurface;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.selected)) {
              return scheme.primaryContainer;
            }
            return scheme.surfaceContainerLowest;
          }),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return scheme.onPrimary;
          return scheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return scheme.primary;
          return scheme.surfaceContainerHigh;
        }),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.primaryContainer,
      ),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      primaryIconTheme: IconThemeData(color: scheme.primary),
    );
  }

  static ThemeData get dark {
    const seed = Color(0xFF4B8BFF);
    final scheme =
        ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: scheme.surface.withValues(alpha: 0.88),
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.88),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
      ),
    );
  }
}
