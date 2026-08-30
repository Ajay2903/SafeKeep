import 'package:flutter/animation.dart';

/// Shared animation timings and curves.
///
/// Centralised so motion feels like one system rather than a collection
/// of independently-guessed numbers. Durations follow the usual rule that
/// larger movements need longer: a colour change is quick, a whole screen
/// transition is not.
///
/// # Accessibility
///
/// Every animation built on these must remain *skippable* — nothing may
/// gate an action behind a completed animation, and no screen may become
/// unusable if the platform reports `disableAnimations`. Motion here is
/// feedback, never a prerequisite.
abstract final class AppMotion {
  /// Colour, opacity, and small state changes on a control.
  static const Duration micro = Duration(milliseconds: 120);

  /// The default for most element-level animation.
  static const Duration short = Duration(milliseconds: 220);

  /// Screen transitions and larger reveals.
  static const Duration medium = Duration(milliseconds: 340);

  /// Deliberate, attention-drawing moments — the vault sealing, a
  /// successful unlock. Long enough to register as meaningful.
  static const Duration long = Duration(milliseconds: 520);

  /// Standard easing for elements entering the screen: fast out of the
  /// gate, settling gently.
  static const Curve enter = Curves.easeOutCubic;

  /// For elements leaving. Quicker than [enter] — waiting for something
  /// to disappear feels like lag.
  static const Curve exit = Curves.easeInCubic;

  /// Both directions, for elements that move within the screen.
  static const Curve standard = Curves.easeInOutCubic;

  /// A restrained overshoot for confirmations. Used sparingly; bounce
  /// undermines the tone everywhere else.
  static const Curve emphasised = Curves.easeOutBack;
}
