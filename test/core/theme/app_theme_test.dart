import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safekeep/core/theme/app_theme.dart';

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
  });
}
