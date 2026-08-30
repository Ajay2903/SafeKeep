import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safekeep/core/constants/app_motion.dart';
import 'package:safekeep/core/constants/app_shape.dart';
import 'package:safekeep/core/constants/app_spacing.dart';
import 'package:safekeep/core/theme/app_colors.dart';
import 'package:safekeep/core/theme/app_text_theme.dart';

/// Light and dark themes.
///
/// Applied once at the app root; screens read `Theme.of(context)` and
/// never construct their own `ThemeData` or hardcode a colour.
///
/// Surfaces are separated by hairline borders rather than drop shadows.
/// On the near-black background used here a soft shadow is invisible at
/// best and a grey smudge at worst, whereas a 1px border stays crisp in
/// both schemes and reads as precise — which is the intended tone.
abstract final class AppTheme {
  static ThemeData get dark => _build(
    brightness: Brightness.dark,
    background: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    surfaceRaised: AppColors.darkSurfaceRaised,
    border: AppColors.darkBorder,
    textPrimary: AppColors.darkTextPrimary,
    textSecondary: AppColors.darkTextSecondary,
    textTertiary: AppColors.darkTextTertiary,
    accentSubtle: AppColors.accentSubtleDark,
    dangerSubtle: AppColors.dangerSubtleDark,
  );

  static ThemeData get light => _build(
    brightness: Brightness.light,
    background: AppColors.lightBackground,
    surface: AppColors.lightSurface,
    surfaceRaised: AppColors.lightSurfaceRaised,
    border: AppColors.lightBorder,
    textPrimary: AppColors.lightTextPrimary,
    textSecondary: AppColors.lightTextSecondary,
    textTertiary: AppColors.lightTextTertiary,
    accentSubtle: AppColors.accentSubtleLight,
    dangerSubtle: AppColors.dangerSubtleLight,
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color surfaceRaised,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
    required Color textTertiary,
    required Color accentSubtle,
    required Color dangerSubtle,
  }) {
    final isDark = brightness == Brightness.dark;
    // The accent is dark enough that white text clears AA contrast in
    // both schemes, so this does not vary by brightness.
    const onAccent = Colors.white;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: AppColors.accent,
      onPrimary: onAccent,
      primaryContainer: accentSubtle,
      onPrimaryContainer: AppColors.accent,
      secondary: textSecondary,
      onSecondary: background,
      error: AppColors.danger,
      onError: Colors.white,
      errorContainer: dangerSubtle,
      onErrorContainer: AppColors.danger,
      surface: surface,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
      surfaceContainerHighest: surfaceRaised,
      outline: border,
      outlineVariant: border,
    );

    final textTheme = AppTextTheme.build(
      primary: textPrimary,
      secondary: textSecondary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      dividerColor: border,
      splashFactory: InkSparkle.splashFactory,

      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleMedium,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),

      dividerTheme: DividerThemeData(
        color: border,
        thickness: AppShape.borderWidth,
        space: AppShape.borderWidth,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: onAccent,
          disabledBackgroundColor: border,
          disabledForegroundColor: textTertiary,
          minimumSize: const Size.fromHeight(54),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppShape.radiusMedium),
          ),
          animationDuration: AppMotion.micro,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          minimumSize: const Size.fromHeight(54),
          textStyle: textTheme.labelLarge,
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppShape.radiusMedium),
          ),
          animationDuration: AppMotion.micro,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppShape.radiusSmall),
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? surfaceRaised : surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        hintStyle: textTheme.bodyLarge?.copyWith(color: textTertiary),
        border: _inputBorder(border),
        enabledBorder: _inputBorder(border),
        focusedBorder: _inputBorder(AppColors.accent, width: 1.5),
        errorBorder: _inputBorder(AppColors.danger),
        focusedErrorBorder: _inputBorder(AppColors.danger, width: 1.5),
        errorStyle: textTheme.bodySmall?.copyWith(color: AppColors.danger),
      ),

      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppShape.radiusLarge),
          side: BorderSide(color: border),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceRaised,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppShape.radiusMedium),
        ),
      ),

      // Screen transitions are handled by the app's own route builders so
      // that motion matches AppMotion rather than each platform's default.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _FadeThroughTransitionBuilder(),
          TargetPlatform.iOS: _FadeThroughTransitionBuilder(),
        },
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppShape.radiusMedium),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}

/// A fade-and-lift page transition.
///
/// Replaces Android's default vertical slide, which is abrupt at these
/// durations. Movement is deliberately small — a large slide would fight
/// the calm the rest of the design is going for.
class _FadeThroughTransitionBuilder extends PageTransitionsBuilder {
  const _FadeThroughTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext? context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: AppMotion.enter,
      reverseCurve: AppMotion.exit,
    );

    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.02),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
