import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safekeep/core/constants/app_motion.dart';
import 'package:safekeep/core/theme/app_colors.dart';
import 'package:safekeep/core/theme/app_theme.dart';

/// Relative luminance per WCAG 2.x.
double _luminance(Color c) {
  double channel(double v) {
    final s = v / 255.0;
    if (s <= 0.03928) return s / 12.92;
    return math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(c.r * 255) +
      0.7152 * channel(c.g * 255) +
      0.0722 * channel(c.b * 255);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('AppTheme', () {
    test('light theme uses light brightness', () {
      expect(AppTheme.light.brightness, Brightness.light);
    });

    test('dark theme uses dark brightness', () {
      expect(AppTheme.dark.brightness, Brightness.dark);
    });

    test('both themes use Material 3', () {
      expect(AppTheme.light.useMaterial3, isTrue);
      expect(AppTheme.dark.useMaterial3, isTrue);
    });

    test('both schemes share the one accent colour', () {
      expect(AppTheme.light.colorScheme.primary, AppColors.accent);
      expect(AppTheme.dark.colorScheme.primary, AppColors.accent);
    });

    test('scaffold backgrounds differ between schemes', () {
      expect(
        AppTheme.light.scaffoldBackgroundColor,
        isNot(AppTheme.dark.scaffoldBackgroundColor),
      );
    });

    test('surfaces are separated by borders, not elevation', () {
      // The design uses hairline borders; a raised card would undercut it.
      expect(AppTheme.dark.cardTheme.elevation, 0);
      expect(AppTheme.dark.appBarTheme.elevation, 0);
    });

    test('a text style is defined for every scale step used', () {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        final text = theme.textTheme;
        expect(text.displaySmall, isNotNull);
        expect(text.headlineMedium, isNotNull);
        expect(text.titleMedium, isNotNull);
        expect(text.bodyLarge, isNotNull);
        expect(text.bodyMedium, isNotNull);
        expect(text.labelLarge, isNotNull);
      }
    });
  });

  group('contrast', () {
    test('body text clears WCAG AA on its background', () {
      // 4.5:1 is the AA threshold for body text. This app is read in
      // varied conditions and must not rely on ideal lighting.
      expect(
        _contrast(AppColors.darkTextPrimary, AppColors.darkBackground),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(AppColors.lightTextPrimary, AppColors.lightBackground),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('secondary text clears WCAG AA on its background', () {
      expect(
        _contrast(AppColors.darkTextSecondary, AppColors.darkBackground),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(AppColors.lightTextSecondary, AppColors.lightBackground),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('white on the accent clears AA, since buttons use it', () {
      expect(
        _contrast(const Color(0xFFFFFFFF), AppColors.accent),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('AppMotion', () {
    test('durations increase with the size of the movement', () {
      expect(AppMotion.micro < AppMotion.short, isTrue);
      expect(AppMotion.short < AppMotion.medium, isTrue);
      expect(AppMotion.medium < AppMotion.long, isTrue);
    });

    test('nothing is slow enough to feel like lag', () {
      // Beyond about half a second a transition stops reading as
      // responsive, however pretty it is.
      expect(AppMotion.long.inMilliseconds, lessThanOrEqualTo(600));
    });
  });
}
