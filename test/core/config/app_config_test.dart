import 'package:flutter_test/flutter_test.dart';
import 'package:safekeep/core/config/app_config.dart';
import 'package:safekeep/core/config/flavor.dart';

void main() {
  group('AppConfig', () {
    test('flavor getters reflect the constructed flavor', () {
      const config = AppConfig(
        flavor: Flavor.staging,
        appName: '[STG] Safekeep',
      );

      expect(config.isStaging, isTrue);
      expect(config.isProduction, isFalse);
      expect(config.isDevelopment, isFalse);
    });
  });

  group('Flavor', () {
    test('isProduction is true only for Flavor.production', () {
      expect(Flavor.production.isProduction, isTrue);
      expect(Flavor.staging.isProduction, isFalse);
      expect(Flavor.development.isProduction, isFalse);
    });
  });
}
