import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safekeep/app/app.dart';
import 'package:safekeep/core/config/app_config.dart';
import 'package:safekeep/core/config/flavor.dart';
import 'package:safekeep/data/database/app_database.dart';
import 'package:safekeep/data/database/database_opener.dart';
import 'package:safekeep/presentation/onboarding/onboarding_flow.dart';
import 'package:safekeep/presentation/unlock/unlock_screen.dart';
import 'package:safekeep/security/auth/biometric_gate.dart';
import 'package:safekeep/security/key_management/key_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeKeyManager implements KeyManager {
  _FakeKeyManager({this.initialized = false});

  bool initialized;
  bool unlocked = false;

  @override
  Future<bool> isInitialized() async => initialized;

  @override
  bool get isUnlocked => unlocked;

  @override
  Future<void> setUpVault({required String passphrase}) async {
    initialized = true;
    unlocked = true;
  }

  @override
  Future<bool> verifyPassphrase(String passphrase) async => true;

  @override
  Future<bool> unlockWithPassphrase(String passphrase) async {
    unlocked = true;
    return true;
  }

  @override
  Future<bool> unlockWithBiometrics() async => false;

  @override
  void lock() => unlocked = false;

  @override
  Future<Uint8List> encryptionKeyFor(String keyId) async => Uint8List(32);

  @override
  Future<Uint8List> databaseKey() async => Uint8List(32);

  @override
  Future<void> deleteVault() async {}
}

class _FakeBiometricGate implements BiometricGate {
  bool available = false;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate({required String reason}) async => false;
}

class _InMemoryOpener implements DatabaseOpener {
  @override
  Future<Database> open({
    required Uint8List key,
    required int version,
    required OnDatabaseCreateFn onCreate,
    required OnDatabaseVersionChangeFn onUpgrade,
  }) {
    return databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: version,
        onCreate: onCreate,
        onUpgrade: onUpgrade,
        // Without this, sqflite caches by path and every test asking for
        // ':memory:' shares one database — including one a previous test
        // already closed. Tests then pass or fail depending on order.
        singleInstance: false,
      ),
    );
  }
}

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory blobDir;

  setUp(() {
    blobDir = Directory.systemTemp.createTempSync('safekeep_app_test');
  });

  tearDown(() {
    if (blobDir.existsSync()) blobDir.deleteSync(recursive: true);
  });

  Widget buildApp({required bool vaultExists}) {
    return App(
      config: const AppConfig(
        flavor: Flavor.development,
        appName: 'Safekeep Test',
      ),
      databasePath: inMemoryDatabasePath,
      blobDirectory: blobDir,
      keyManager: _FakeKeyManager(initialized: vaultExists),
      biometricGate: _FakeBiometricGate(),
      database: AppDatabase(opener: _InMemoryOpener()),
    );
  }

  group('App', () {
    testWidgets('shows onboarding when no vault exists', (tester) async {
      await tester.pumpWidget(buildApp(vaultExists: false));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingFlow), findsOneWidget);
      expect(find.byType(UnlockScreen), findsNothing);
    });

    testWidgets('shows the unlock screen when a vault exists', (tester) async {
      await tester.pumpWidget(buildApp(vaultExists: true));
      await tester.pumpAndSettle();

      expect(find.byType(UnlockScreen), findsOneWidget);
      expect(find.byType(OnboardingFlow), findsNothing);
    });

    testWidgets('never lands on an unlocked screen without unlocking', (
      tester,
    ) async {
      // The whole point of the gate: an existing vault opens sealed.
      await tester.pumpWidget(buildApp(vaultExists: true));
      await tester.pumpAndSettle();

      expect(find.text('Your vault is open'), findsNothing);
    });
  });
}
