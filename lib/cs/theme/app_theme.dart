import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_typography.dart';

/// Control Surface — Material 3 theme (dark-first).
/// Single orange seed = focus + brand. Card/row fills use the custom cream token
/// (AppColors.surface), NOT scheme.surface, because the design puts cream cards on
/// a dark canvas — so read AppColors directly for those rather than the scheme.
///
/// Fonts are bundled locally ('Sora' + 'Space Mono'); body default is Space Mono,
/// titles/names use AppType.* (Sora) explicitly.
class AppTheme {
  AppTheme._();

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.focus,       // focus ring / selected
      secondary: AppColors.accent,    // brand orange
      surface: AppColors.background,  // app bg
      error: AppColors.error,
      onSurface: AppColors.textPrimary,
    );
    return _build(scheme, Brightness.dark);
  }

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.focus,
      secondary: AppColors.accent,
      surface: AppColorsLight.background,
      error: AppColors.error,
      onSurface: AppColorsLight.textPrimary,
    );
    return _build(scheme, Brightness.light);
  }

  static ThemeData _build(ColorScheme scheme, Brightness b) {
    final baseTheme = b == Brightness.dark ? ThemeData.dark() : ThemeData.light();
    // Body default is Space Mono; titles/names use AppType.* (Sora) explicitly.
    final textTheme = baseTheme.textTheme.apply(fontFamily: AppType.fontMono).copyWith(
          displayLarge:  AppType.heroTitle,
          displayMedium: AppType.screenTitle,
          headlineLarge: AppType.drillHeader,
          titleLarge:    AppType.cardTitle,
          titleMedium:   AppType.listTitle,
          labelLarge:    AppType.buttonLabel,
          bodyMedium:    AppType.meta,
          labelSmall:    AppType.microLabel,
        );
    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      fontFamily: AppType.fontMono,
      textTheme: textTheme,
    );
  }
}
