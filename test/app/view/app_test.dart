// Ignore for testing purposes
// ignore_for_file: prefer_const_constructors

import 'package:flutter_test/flutter_test.dart';
import 'package:safekeep/app/app.dart';
import 'package:safekeep/core/config/app_config.dart';
import 'package:safekeep/core/config/flavor.dart';
import 'package:safekeep/counter/counter.dart';

void main() {
  group('App', () {
    testWidgets('renders CounterPage', (tester) async {
      await tester.pumpWidget(
        App(
          config: const AppConfig(
            flavor: Flavor.development,
            appName: 'Safekeep Test',
          ),
        ),
      );
      expect(find.byType(CounterPage), findsOneWidget);
    });
  });
}
