import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safekeep/data/database/app_database.dart';
import 'package:safekeep/data/database/database_opener.dart';
import 'package:safekeep/data/reminders/reminder_scheduler.dart';
import 'package:safekeep/domain/models/document.dart';
import 'package:safekeep/domain/models/document_category.dart';
import 'package:safekeep/domain/models/reminder_settings.dart';
import 'package:safekeep/domain/repositories/document_repository.dart';
import 'package:safekeep/presentation/app/vault_session_cubit.dart';
import 'package:safekeep/presentation/app/vault_session_state.dart';
import 'package:safekeep/security/auth/biometric_gate.dart';
import 'package:safekeep/security/key_management/key_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Scriptable key manager. The real one is covered by its own suite; here
/// only the cubit's reactions to its answers are under test.
class _FakeKeyManager implements KeyManager {
  bool initialized = false;
  bool unlocked = false;
  bool passphraseCorrect = true;
  bool biometricUnlockSucceeds = true;
  int lockCalls = 0;

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
  Future<bool> verifyPassphrase(String passphrase) async => passphraseCorrect;

  @override
  Future<bool> unlockWithPassphrase(String passphrase) async {
    unlocked = passphraseCorrect;
    return passphraseCorrect;
  }

  /// When set, unlockWithBiometrics throws instead of returning —
  /// mirroring a gate that could not run at all.
  String? unavailableMessage;

  @override
  Future<bool> unlockWithBiometrics() async {
    final failure = unavailableMessage;
    if (failure != null) throw BiometricUnavailableException(failure);
    unlocked = biometricUnlockSucceeds;
    return biometricUnlockSucceeds;
  }

  @override
  void lock() {
    lockCalls++;
    unlocked = false;
  }

  @override
  Future<Uint8List> encryptionKeyFor(String keyId) async => Uint8List(32);

  @override
  Future<Uint8List> databaseKey() async => Uint8List(32);

  int deleteVaultCalls = 0;

  @override
  Future<void> deleteVault() async {
    deleteVaultCalls++;
    initialized = false;
    unlocked = false;
  }
}

class _FakeBiometricGate implements BiometricGate {
  bool available = true;
  BiometricCapability reportedCapability = BiometricCapability.fingerprint;

  /// When set, authenticate() throws instead of returning — simulating a
  /// device with nothing enrolled, or a locked-out sensor.
  String? unavailableMessage;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<BiometricCapability> capability() async =>
      // A gate that reports nothing available cannot also claim a
      // fingerprint; keeping the fake coherent stops tests asserting a
      // state the real gate could never produce.
      available ? reportedCapability : BiometricCapability.none;

  @override
  Future<bool> authenticate({required String reason}) async {
    final failure = unavailableMessage;
    if (failure != null) throw BiometricUnavailableException(failure);
    return true;
  }
}

/// Records the erase path without touching real storage.
class _FakeRepository implements DocumentRepository {
  int deleteAllCalls = 0;

  @override
  Future<void> deleteAllDocuments() async => deleteAllCalls++;

  @override
  Future<List<Document>> listDocuments() async => [];

  @override
  Future<Document?> getDocument(String id) async => null;

  @override
  Future<Uint8List> openDocument(String id) async => Uint8List(0);

  @override
  Future<void> deleteDocument(String id) async {}

  @override
  Future<Document> updateDocument(Document document) async => document;

  @override
  Future<Document> addDocument({
    required Uint8List bytes,
    required String title,
    required DocumentCategory category,
    required String mimeType,
    List<String> tags = const [],
    String? notes,
    DateTime? expiresAt,
  }) async => throw UnimplementedError();
}

class _FakeReminders implements ReminderScheduler {
  int cancelAllCalls = 0;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> scheduleFor({
    required String documentId,
    required DateTime expiresAt,
    required ReminderSettings settings,
  }) async {}

  @override
  Future<void> cancelFor(String documentId) async {}

  @override
  Future<void> cancelAll() async => cancelAllCalls++;
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

  late _FakeKeyManager keyManager;
  late _FakeBiometricGate gate;
  late _FakeRepository repository;
  late _FakeReminders reminders;
  late AppDatabase database;

  setUp(() {
    keyManager = _FakeKeyManager();
    gate = _FakeBiometricGate();
    repository = _FakeRepository();
    reminders = _FakeReminders();
    database = AppDatabase(opener: _InMemoryOpener());
  });

  VaultSessionCubit build() => VaultSessionCubit(
    keyManager: keyManager,
    biometricGate: gate,
    database: database,
    repository: repository,
    reminders: reminders,
  );

  group('checkStatus', () {
    blocTest<VaultSessionCubit, VaultSessionState>(
      'reports uninitialized when no vault exists',
      build: build,
      act: (cubit) => cubit.checkStatus(),
      expect: () => [const VaultUninitialized()],
    );

    blocTest<VaultSessionCubit, VaultSessionState>(
      'reports locked when a vault exists',
      build: build,
      setUp: () => keyManager.initialized = true,
      act: (cubit) => cubit.checkStatus(),
      expect: () => [
        const VaultLocked(
          biometricsAvailable: true,
          capability: BiometricCapability.fingerprint,
        ),
      ],
    );

    blocTest<VaultSessionCubit, VaultSessionState>(
      'reports biometrics unavailable when none are enrolled',
      build: build,
      setUp: () {
        keyManager.initialized = true;
        gate.available = false;
      },
      act: (cubit) => cubit.checkStatus(),
      expect: () => [const VaultLocked()],
    );

    test('starts in the checking state', () {
      expect(build().state, isA<VaultChecking>());
    });
  });

  group('createVault', () {
    blocTest<VaultSessionCubit, VaultSessionState>(
      'passes through setting-up and lands unlocked',
      build: build,
      act: (cubit) => cubit.createVault('correct horse battery staple'),
      expect: () => [const VaultSettingUp(), const VaultUnlocked()],
      verify: (_) => expect(database.isOpen, isTrue),
    );

    blocTest<VaultSessionCubit, VaultSessionState>(
      'opens the metadata database as part of opening the vault',
      build: build,
      act: (cubit) => cubit.createVault('passphrase'),
      verify: (_) => expect(database.isOpen, isTrue),
    );
  });

  group('unlockWithPassphrase', () {
    blocTest<VaultSessionCubit, VaultSessionState>(
      'passes through unlocking and lands unlocked',
      build: build,
      setUp: () => keyManager.initialized = true,
      act: (cubit) => cubit.unlockWithPassphrase('right'),
      expect: () => [const VaultUnlocking(), const VaultUnlocked()],
    );

    blocTest<VaultSessionCubit, VaultSessionState>(
      'flags a wrong passphrase and stays locked',
      build: build,
      setUp: () => keyManager
        ..initialized = true
        ..passphraseCorrect = false,
      act: (cubit) => cubit.unlockWithPassphrase('wrong'),
      expect: () => [
        const VaultUnlocking(),
        const VaultLocked(
          biometricsAvailable: true,
          lastAttemptFailed: true,
          capability: BiometricCapability.fingerprint,
        ),
      ],
      verify: (_) => expect(database.isOpen, isFalse),
    );
  });

  group('capability reporting', () {
    // The unlock button is labelled from this. A device with no
    // fingerprint enrolled still authenticates via the screen lock, so
    // calling that button "biometrics" would be untrue.
    blocTest<VaultSessionCubit, VaultSessionState>(
      'reports the screen lock when no biometric is enrolled',
      build: build,
      setUp: () {
        keyManager.initialized = true;
        gate.reportedCapability = BiometricCapability.deviceCredential;
      },
      act: (cubit) => cubit.checkStatus(),
      verify: (cubit) => expect(
        (cubit.state as VaultLocked).capability,
        BiometricCapability.deviceCredential,
      ),
    );

    blocTest<VaultSessionCubit, VaultSessionState>(
      'reports fingerprint when one is enrolled',
      build: build,
      setUp: () {
        keyManager.initialized = true;
        gate.reportedCapability = BiometricCapability.fingerprint;
      },
      act: (cubit) => cubit.checkStatus(),
      verify: (cubit) => expect(
        (cubit.state as VaultLocked).capability,
        BiometricCapability.fingerprint,
      ),
    );
  });

  group('biometrics unavailable', () {
    // A silent failure here is what made a real misconfiguration look
    // like a dead button: local_auth cannot attach its prompt to a
    // non-FragmentActivity, the gate swallowed the exception, and
    // tapping "Unlock with biometrics" simply did nothing.
    blocTest<VaultSessionCubit, VaultSessionState>(
      'reports why, instead of failing silently',
      build: build,
      setUp: () {
        keyManager
          ..initialized = true
          ..unavailableMessage = 'No fingerprint is set up on this device.';
      },
      act: (cubit) async {
        await cubit.checkStatus();
        await cubit.unlockWithBiometrics();
      },
      verify: (cubit) {
        final state = cubit.state;
        expect(state, isA<VaultLocked>());
        expect(
          (state as VaultLocked).biometricMessage,
          'No fingerprint is set up on this device.',
        );
      },
    );

    blocTest<VaultSessionCubit, VaultSessionState>(
      'stays locked when biometrics cannot run',
      build: build,
      setUp: () {
        keyManager
          ..initialized = true
          ..unavailableMessage = 'Locked out.';
      },
      act: (cubit) async {
        await cubit.checkStatus();
        await cubit.unlockWithBiometrics();
      },
      verify: (cubit) => expect(cubit.state, isA<VaultLocked>()),
    );

    blocTest<VaultSessionCubit, VaultSessionState>(
      'a dismissed prompt carries no message',
      build: build,
      setUp: () {
        keyManager
          ..initialized = true
          ..biometricUnlockSucceeds = false;
      },
      act: (cubit) async {
        await cubit.checkStatus();
        await cubit.unlockWithBiometrics();
      },
      verify: (cubit) {
        // Dismissing is deliberate; explaining it would be noise.
        expect((cubit.state as VaultLocked).biometricMessage, isNull);
      },
    );
  });

  group('unlockWithBiometrics', () {
    blocTest<VaultSessionCubit, VaultSessionState>(
      'unlocks on success',
      build: build,
      setUp: () => keyManager.initialized = true,
      act: (cubit) => cubit.unlockWithBiometrics(),
      expect: () => [const VaultUnlocked()],
    );

    blocTest<VaultSessionCubit, VaultSessionState>(
      'a cancelled prompt is not reported as a failed attempt',
      build: build,
      setUp: () => keyManager
        ..initialized = true
        ..biometricUnlockSucceeds = false,
      act: (cubit) => cubit.unlockWithBiometrics(),
      // lastAttemptFailed stays false: the user dismissed the sheet,
      // which is not the same as getting it wrong.
      expect: () => [
        const VaultLocked(
          biometricsAvailable: true,
          capability: BiometricCapability.fingerprint,
        ),
      ],
    );
  });

  group('deleteEverything', () {
    blocTest<VaultSessionCubit, VaultSessionState>(
      'erases documents, reminders, and the vault',
      build: build,
      setUp: () => keyManager
        ..initialized = true
        ..passphraseCorrect = true,
      act: (cubit) async {
        await cubit.checkStatus();
        await cubit.deleteEverything('correct');
      },
      verify: (cubit) {
        expect(repository.deleteAllCalls, 1);
        expect(reminders.cancelAllCalls, 1);
        expect(keyManager.deleteVaultCalls, 1);
        // Back to onboarding: there is no vault left to unlock.
        expect(cubit.state, isA<VaultUninitialized>());
      },
    );

    blocTest<VaultSessionCubit, VaultSessionState>(
      'a wrong passphrase changes nothing at all',
      build: build,
      setUp: () => keyManager
        ..initialized = true
        ..passphraseCorrect = false,
      act: (cubit) async {
        await cubit.checkStatus();
        await cubit.deleteEverything('wrong');
      },
      verify: (cubit) {
        // Nothing is touched — not the documents, not the reminders, not
        // the key. An erase that half-ran on a wrong passphrase would be
        // the worst possible outcome.
        expect(repository.deleteAllCalls, 0);
        expect(reminders.cancelAllCalls, 0);
        expect(keyManager.deleteVaultCalls, 0);
        expect(cubit.state, isA<VaultLocked>());
      },
    );

    test('reports whether it erased', () async {
      keyManager
        ..initialized = true
        ..passphraseCorrect = false;
      final cubit = build();

      expect(await cubit.deleteEverything('wrong'), isFalse);

      keyManager.passphraseCorrect = true;
      expect(await cubit.deleteEverything('right'), isTrue);
      await cubit.close();
    });

    test('closes the metadata database', () async {
      keyManager
        ..initialized = true
        ..passphraseCorrect = true;
      final cubit = build();
      await cubit.createVault('passphrase');
      expect(database.isOpen, isTrue);

      await cubit.deleteEverything('passphrase');

      // Leaving it open would keep decrypted pages in SQLCipher's cache
      // after the key they belong to has been destroyed.
      expect(database.isOpen, isFalse);
      await cubit.close();
    });
  });

  group('lock', () {
    blocTest<VaultSessionCubit, VaultSessionState>(
      'clears keys, closes the database, and returns to locked',
      build: build,
      act: (cubit) async {
        await cubit.createVault('passphrase');
        cubit.lock();
      },
      expect: () => [
        const VaultSettingUp(),
        const VaultUnlocked(),
        const VaultLocked(
          biometricsAvailable: true,
          capability: BiometricCapability.fingerprint,
        ),
      ],
      verify: (_) {
        expect(keyManager.lockCalls, 1);
        expect(keyManager.isUnlocked, isFalse);
      },
    );

    test('closes the metadata database', () async {
      final cubit = build();
      await cubit.createVault('passphrase');
      expect(database.isOpen, isTrue);

      cubit.lock();
      // The close is deliberately not awaited so the state lands in the
      // same frame; give it a turn of the event loop.
      await Future<void>.delayed(Duration.zero);

      expect(database.isOpen, isFalse);
      await cubit.close();
    });

    blocTest<VaultSessionCubit, VaultSessionState>(
      'is safe to call twice',
      build: build,
      act: (cubit) async {
        await cubit.createVault('passphrase');
        cubit
          ..lock()
          ..lock();
      },
      verify: (_) => expect(keyManager.isUnlocked, isFalse),
    );
  });

  group('auto-lock wiring', () {
    test('backgrounding past the grace period locks the vault', () async {
      final cubit = VaultSessionCubit(
        keyManager: keyManager,
        biometricGate: gate,
        database: database,
        repository: repository,
        reminders: reminders,
        backgroundGracePeriod: const Duration(milliseconds: 40),
      );
      await cubit.createVault('passphrase');
      expect(cubit.state, isA<VaultUnlocked>());

      cubit.onAppBackgrounded();
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(cubit.state, isA<VaultLocked>());
      expect(keyManager.isUnlocked, isFalse);
      await cubit.close();
    });

    test('returning to the foreground in time keeps the vault open', () async {
      final cubit = VaultSessionCubit(
        keyManager: keyManager,
        biometricGate: gate,
        database: database,
        repository: repository,
        reminders: reminders,
        backgroundGracePeriod: const Duration(milliseconds: 200),
      );
      await cubit.createVault('passphrase');

      cubit.onAppBackgrounded();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      cubit.onAppForegrounded();
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(cubit.state, isA<VaultUnlocked>());
      await cubit.close();
    });

    test('idling past the timeout locks the vault', () async {
      final cubit = VaultSessionCubit(
        keyManager: keyManager,
        biometricGate: gate,
        database: database,
        repository: repository,
        reminders: reminders,
        inactivityTimeout: const Duration(milliseconds: 40),
      );
      await cubit.createVault('passphrase');

      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(cubit.state, isA<VaultLocked>());
      await cubit.close();
    });

    test('interaction defers the idle lock', () async {
      final cubit = VaultSessionCubit(
        keyManager: keyManager,
        biometricGate: gate,
        database: database,
        repository: repository,
        reminders: reminders,
        inactivityTimeout: const Duration(milliseconds: 100),
      );
      await cubit.createVault('passphrase');

      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        cubit.recordInteraction();
      }

      expect(cubit.state, isA<VaultUnlocked>());
      await cubit.close();
    });
  });
}
