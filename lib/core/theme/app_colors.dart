import 'package:flutter/material.dart';

/// Single source of truth for the app's brand color.
///
/// Light/dark [ColorScheme]s are derived from this seed via Material 3's
/// tonal palette generation ([ColorScheme.fromSeed]), which guarantees
/// accessible contrast between roles without hand-picking every shade.
abstract final class AppColors {
  /// A deep, muted blue — chosen to read as calm and trustworthy rather
  /// than playful, appropriate for a security/privacy product.
  static const Color seed = Color(0xFF2C5C8A);
}
