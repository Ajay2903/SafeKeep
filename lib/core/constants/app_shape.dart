/// Corner radii.
///
/// A small, fixed set so nested surfaces stay visually consistent. Radii
/// are on the restrained side: heavily rounded corners read as friendly
/// and casual, which is the wrong register for a vault.
abstract final class AppShape {
  /// Chips, badges, small indicators.
  static const double radiusSmall = 8;

  /// Buttons, inputs — the default for interactive elements.
  static const double radiusMedium = 12;

  /// Cards and panels.
  static const double radiusLarge = 16;

  /// Sheets and full-width containers.
  static const double radiusXLarge = 24;

  /// Hairline borders. Surfaces are separated by a 1px border rather than
  /// a drop shadow: borders stay crisp on dark backgrounds, where soft
  /// shadows are nearly invisible and tend to look like smudges.
  static const double borderWidth = 1;
}
