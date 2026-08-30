import 'package:flutter/material.dart';

/// The app's colour palette.
///
/// # Why these are hand-picked rather than seed-generated
///
/// Phase 0 generated both schemes from a single seed via
/// `ColorScheme.fromSeed`, which is a fine default but produces the
/// slightly lilac, high-chroma surfaces characteristic of Material 3's
/// tonal palettes. For a product whose job is to feel like a safe, that
/// reads as playful rather than serious.
///
/// These roles are therefore specified directly: deep, desaturated
/// backgrounds, restrained chroma, and a single accent used sparingly so
/// it means something when it appears. Contrast ratios for text on
/// surfaces were chosen to clear WCAG AA (4.5:1 for body text).
abstract final class AppColors {
  // ---------------------------------------------------------------- dark

  /// Near-black with a blue cast, rather than pure black: pure black
  /// against bright text causes halation on OLED, and a slight hue makes
  /// the surface feel deliberate instead of absent.
  static const Color darkBackground = Color(0xFF0B0F14);
  static const Color darkSurface = Color(0xFF11161D);
  static const Color darkSurfaceRaised = Color(0xFF181F28);
  static const Color darkBorder = Color(0xFF232C38);

  static const Color darkTextPrimary = Color(0xFFE8EDF4);
  static const Color darkTextSecondary = Color(0xFF97A3B4);
  static const Color darkTextTertiary = Color(0xFF5F6C7E);

  // --------------------------------------------------------------- light

  static const Color lightBackground = Color(0xFFF7F8FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceRaised = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE2E6EC);

  static const Color lightTextPrimary = Color(0xFF0D1117);
  static const Color lightTextSecondary = Color(0xFF56616F);
  static const Color lightTextTertiary = Color(0xFF8A94A2);

  // -------------------------------------------------------------- accent

  /// The single accent. A cool, slightly muted blue — confident without
  /// the saturation of a consumer-app brand colour.
  ///
  /// Darkened from an initial brighter blue (#3D7EFF) because white text
  /// on it measured only 3.73:1, below the 4.5:1 WCAG AA threshold.
  /// Button labels here are 15px semibold, which does *not* meet WCAG's
  /// definition of large text (18.66px bold or 24px regular), so the
  /// relaxed 3:1 threshold does not apply. This value measures 4.61:1 and
  /// is verified by a test.
  static const Color accent = Color(0xFF2F6FE8);
  static const Color accentPressed = Color(0xFF2559C4);
  static const Color accentSubtleDark = Color(0xFF16233A);
  static const Color accentSubtleLight = Color(0xFFEBF1FF);

  /// Reserved for the unrecoverable-passphrase warning and destructive
  /// actions. Deliberately the only warm colour in the palette, so it
  /// cannot be confused with anything routine.
  static const Color danger = Color(0xFFE5484D);
  static const Color dangerSubtleDark = Color(0xFF2A1416);
  static const Color dangerSubtleLight = Color(0xFFFFF0F0);

  /// Confirmation of a completed secure action.
  static const Color success = Color(0xFF30A46C);
}
