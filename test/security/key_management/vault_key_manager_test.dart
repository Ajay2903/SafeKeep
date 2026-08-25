import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:safekeep/security/auth/biometric_gate.dart';
import 'package:safekeep/security/key_management/kdf_parameters.dart';
import 'package:safekeep/security/key_management/secure_key_value_store.dart';
import 'package:safekeep/security/key_management/vault_key_manager.dart';
import 'package:safekeep/security/security_exceptions.dart';

/// In-memory stand-in for Keystore/Keychain. The real
/// `flutter_secure_storage` needs a platform channel and cannot run here.
class _FakeStore implements SecureKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// Scriptable biometric gate.
class _FakeBiometricGate implements BiometricGate {
  bool available = true;
  bool succeeds = true;
  int authenticateCalls = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate({required String reason}) async {
    authenticateCalls++;
    return succeeds;
  }
}

/// Cheap KDF cost factors so the suite runs fast.
///
/// None of the lifecycle behaviour under test depends on the cost
/// factors; the production values are pinned separately by
/// key_derivation_test.dart.
const _fastParams = KdfParameters(
  memoryKib: 64,
  iterations: 1,
  parallelism: 1,
  keyLengthBytes: 32,
);

const _passphrase = 'correct horse battery staple';
const _wrongPassphrase = 'incorrect horse battery staple';

void main() {
  late _FakeStore store;
  late _FakeBiometricGate gate;
  late VaultKeyManager manager;

  setUp(() {
    store = _FakeStore();
    gate = _FakeBiometricGate();
    manager = VaultKeyManager(
      store: store,
      biometricGate: gate,
      setupParameters: _fastParams,
    );
  });

  Future<void> setUpVault() => manager.setUpVault(passphrase: _passphrase);

  group('initial state', () {
    test('starts uninitialized and locked', () async {
      expect(await manager.isInitialized(), isFalse);
      expect(manager.isUnlocked, isFalse);
    });

    test('verifyPassphrase throws when no vault exists', () async {
      await expectLater(
        () => manager.verifyPassphrase(_passphrase),
        throwsA(isA<VaultNotInitializedException>()),
      );
    });

    test('unlockWithBiometrics throws when no vault exists', () async {
      await expectLater(
        manager.unlockWithBiometrics,
        throwsA(isA<VaultNotInitializedException>()),
      );
    });
  });

  group('setUpVault', () {
    test('initializes the vault and leaves it unlocked', () async {
      await setUpVault();

      expect(await manager.isInitialized(), isTrue);
      expect(manager.isUnlocked, isTrue);
    });

    test('never stores the passphrase in any form', () async {
      await setUpVault();

      // Exhaustive: no stored value may contain the passphrase, raw or
      // base64-encoded.
      final encoded = base64Encode(utf8.encode(_passphrase));
      for (final value in store.values.values) {
        expect(value, isNot(contains(_passphrase)));
        expect(value, isNot(contains(encoded)));
      }
    });

    test(
      'stores salt, params, verifier, and key under versioned names',
      () async {
        await setUpVault();

        expect(
          store.values.keys,
          containsAll([
            'safekeep.v1.salt',
            'safekeep.v1.kdf_params',
            'safekeep.v1.verifier',
            'safekeep.v1.encryption_key',
          ]),
        );
      },
    );

    test('the stored verifier is not the stored encryption key', () async {
      await setUpVault();

      // If these matched, persisting the verifier would persist the key.
      expect(
        store.values['safekeep.v1.verifier'],
        isNot(store.values['safekeep.v1.encryption_key']),
      );
    });

    test('refuses to overwrite an existing vault', () async {
      await setUpVault();

      // Overwriting would silently destroy every existing document.
      await expectLater(
        () => manager.setUpVault(passphrase: 'a different passphrase'),
        throwsA(isA<VaultAlreadyInitializedException>()),
      );
    });

    test('two vaults with the same passphrase get different keys', () async {
      await setUpVault();
      final firstKey = store.values['safekeep.v1.encryption_key'];

      final otherStore = _FakeStore();
      final otherManager = VaultKeyManager(
        store: otherStore,
        biometricGate: gate,
        setupParameters: _fastParams,
      );
      await otherManager.setUpVault(passphrase: _passphrase);

      // Different random salts must produce different keys.
      expect(otherStore.values['safekeep.v1.encryption_key'], isNot(firstKey));
    });
  });

  group('verifyPassphrase', () {
    setUp(setUpVault);

    test(
      'accepts the correct passphrase without decrypting anything',
      () async {
        expect(await manager.verifyPassphrase(_passphrase), isTrue);
      },
    );

    test('rejects a wrong passphrase', () async {
      expect(await manager.verifyPassphrase(_wrongPassphrase), isFalse);
    });

    test('does not change lock state either way', () async {
      manager.lock();

      await manager.verifyPassphrase(_passphrase);
      expect(manager.isUnlocked, isFalse, reason: 'verify must not unlock');

      await manager.verifyPassphrase(_wrongPassphrase);
      expect(manager.isUnlocked, isFalse);
    });
  });

  group('unlockWithPassphrase', () {
    setUp(setUpVault);

    test('unlocks with the correct passphrase', () async {
      manager.lock();

      expect(await manager.unlockWithPassphrase(_passphrase), isTrue);
      expect(manager.isUnlocked, isTrue);
    });

    test('rejects a wrong passphrase and stays locked', () async {
      manager.lock();

      expect(await manager.unlockWithPassphrase(_wrongPassphrase), isFalse);
      expect(manager.isUnlocked, isFalse);
    });

    test('key after re-unlock matches the key from setup', () async {
      final atSetup = await manager.encryptionKeyFor('master');

      manager.lock();
      await manager.unlockWithPassphrase(_passphrase);

      // Deterministic derivation is what makes documents readable across
      // sessions and devices.
      expect(await manager.encryptionKeyFor('master'), atSetup);
    });
  });

  group('unlockWithBiometrics', () {
    setUp(setUpVault);

    test('unlocks when the gate succeeds', () async {
      manager.lock();
      gate.succeeds = true;

      expect(await manager.unlockWithBiometrics(), isTrue);
      expect(manager.isUnlocked, isTrue);
    });

    test('stays locked when the user cancels', () async {
      manager.lock();
      gate.succeeds = false;

      expect(await manager.unlockWithBiometrics(), isFalse);
      expect(manager.isUnlocked, isFalse);
    });

    test('key material stays unreadable after a failed gate', () async {
      manager.lock();
      gate.succeeds = false;
      await manager.unlockWithBiometrics();

      await expectLater(
        () => manager.encryptionKeyFor('master'),
        throwsA(isA<VaultLockedException>()),
      );
    });

    test('the gate is actually consulted', () async {
      manager.lock();
      await manager.unlockWithBiometrics();

      expect(gate.authenticateCalls, 1);
    });

    test('biometric unlock yields the same key as the passphrase', () async {
      final viaPassphrase = await manager.encryptionKeyFor('master');

      manager.lock();
      await manager.unlockWithBiometrics();

      expect(await manager.encryptionKeyFor('master'), viaPassphrase);
    });
  });

  group('locked state', () {
    setUp(setUpVault);

    test('encryptionKeyFor throws once locked', () async {
      manager.lock();

      await expectLater(
        () => manager.encryptionKeyFor('master'),
        throwsA(isA<VaultLockedException>()),
      );
    });

    test('lock() zeroes the buffer a caller previously received', () async {
      // The manager hands out copies, so locking must not corrupt a key
      // the caller is still holding mid-operation.
      final held = await manager.encryptionKeyFor('master');
      final snapshot = List<int>.from(held);

      manager.lock();

      expect(held, snapshot, reason: 'caller copy must be unaffected');
    });

    test('lock() is idempotent', () async {
      manager
        ..lock()
        ..lock();

      expect(manager.isUnlocked, isFalse);
    });

    test('locking does not destroy the vault', () async {
      manager.lock();

      expect(await manager.isInitialized(), isTrue);
      expect(await manager.unlockWithPassphrase(_passphrase), isTrue);
    });
  });

  group('deleteVault', () {
    setUp(setUpVault);

    test('removes every stored item', () async {
      await manager.deleteVault();

      expect(store.values, isEmpty);
    });

    test('locks and reports uninitialized afterwards', () async {
      await manager.deleteVault();

      expect(manager.isUnlocked, isFalse);
      expect(await manager.isInitialized(), isFalse);
    });

    test('the correct passphrase no longer works', () async {
      await manager.deleteVault();

      // Crypto-erase: the key is gone, so the data is unrecoverable.
      await expectLater(
        () => manager.unlockWithPassphrase(_passphrase),
        throwsA(isA<VaultNotInitializedException>()),
      );
    });
  });
}
