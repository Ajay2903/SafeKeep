import 'package:flutter/material.dart';

/// App-wide type scale, layered on top of Material 3's default [TextTheme].
///
/// Kept intentionally minimal for Phase 0 — a custom font can be dropped in
/// here later (e.g. via `google_fonts` or a bundled font asset) without
/// touching call sites, since screens should reference `Theme.of(context)
/// .textTheme` rather than this class directly.
abstract final class AppTextTheme {
  static TextTheme build(ColorScheme colorScheme) {
    final base = Typography.material2021().black;
    return base.apply(
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
    );
  }
}
