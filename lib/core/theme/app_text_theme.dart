import 'package:flutter/material.dart';
import 'package:safekeep/core/theme/app_colors.dart';

/// The app's type scale.
///
/// # Why no custom font package
///
/// `google_fonts` is the usual reach for a "premium" type scale, but it
/// downloads font files over the network at first use. For an app whose
/// whole claim is that it works offline and makes no network requests,
/// that is a contradiction, not just an extra dependency — it would put
/// a request to a third party into the launch path of a privacy tool.
///
/// The platform's own UI font is used instead (SF Pro on iOS, Roboto on
/// Android), shaped with deliberate weights, sizes, and letter-spacing.
/// If a bundled typeface is wanted later, ship the file as an asset so
/// it stays offline.
///
/// # Choices
///
/// Display and headline sizes are tightened (negative letter-spacing),
/// which is what makes large text read as designed rather than merely
/// enlarged. Body text keeps neutral spacing and a generous line height
/// for readability. Labels are slightly wider-tracked, which helps small
/// uppercase-ish UI text stay legible.
abstract final class AppTextTheme {
  static TextTheme build({
    required Color primary,
    required Color secondary,
  }) {
    return TextTheme(
      displaySmall: TextStyle(
        fontSize: 34,
        height: 1.15,
        letterSpacing: -0.8,
        fontWeight: FontWeight.w700,
        color: primary,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        height: 1.2,
        letterSpacing: -0.6,
        fontWeight: FontWeight.w700,
        color: primary,
      ),
      headlineSmall: TextStyle(
        fontSize: 22,
        height: 1.25,
        letterSpacing: -0.4,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      titleMedium: TextStyle(
        fontSize: 17,
        height: 1.35,
        letterSpacing: -0.2,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      titleSmall: TextStyle(
        fontSize: 15,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        height: 1.55,
        fontWeight: FontWeight.w400,
        color: primary,
      ),
      bodyMedium: TextStyle(
        fontSize: 15,
        height: 1.55,
        fontWeight: FontWeight.w400,
        color: secondary,
      ),
      bodySmall: TextStyle(
        fontSize: 13,
        height: 1.5,
        fontWeight: FontWeight.w400,
        color: secondary,
      ),
      labelLarge: TextStyle(
        fontSize: 15,
        height: 1.2,
        letterSpacing: 0.1,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      labelMedium: TextStyle(
        fontSize: 13,
        height: 1.2,
        letterSpacing: 0.2,
        fontWeight: FontWeight.w500,
        color: secondary,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        height: 1.2,
        letterSpacing: 0.4,
        fontWeight: FontWeight.w600,
        color: secondary,
      ),
    );
  }

  /// Monospaced style for anything that must be read character by
  /// character — key fingerprints, recovery data, diagnostic output.
  ///
  /// Never used for document contents.
  static TextStyle mono({required Color color, double fontSize = 13}) {
    return TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Roboto Mono', 'Courier'],
      fontSize: fontSize,
      height: 1.5,
      color: color,
    );
  }

  /// Convenience for the dark scheme.
  static TextTheme get dark => build(
    primary: AppColors.darkTextPrimary,
    secondary: AppColors.darkTextSecondary,
  );

  /// Convenience for the light scheme.
  static TextTheme get light => build(
    primary: AppColors.lightTextPrimary,
    secondary: AppColors.lightTextSecondary,
  );
}
