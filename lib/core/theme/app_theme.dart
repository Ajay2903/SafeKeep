import 'package:flutter/material.dart';
import 'package:safekeep/core/theme/app_colors.dart';
import 'package:safekeep/core/theme/app_text_theme.dart';

/// Light and dark [ThemeData] for the app, built from [AppColors.seed].
///
/// Applied once at the app root (see `lib/app/view/app.dart`) via
/// `MaterialApp.theme` / `MaterialApp.darkTheme`; screens should never
/// construct their own `ThemeData` or hardcode colors.
abstract final class AppTheme {
  static ThemeData get light => _themeFor(Brightness.light);

  static ThemeData get dark => _themeFor(Brightness.dark);

  static ThemeData _themeFor(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.seed,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: AppTextTheme.build(colorScheme),
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      scaffoldBackgroundColor: colorScheme.surface,
    );
  }
}
