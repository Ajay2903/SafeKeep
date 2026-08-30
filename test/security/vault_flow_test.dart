import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:safekeep/security/auth/biometric_gate.dart';
import 'package:safekeep/security/encryption/aes_gcm_encryption_service.dart';
import 'package:safekeep/security/key_management/auto_lock_controller.dart';
import 'package:safekeep/security/key_management/kdf_parameters.dart';
import 'package:safekeep/security/key_management/secure_key_value_store.dart';
import 'package:safekeep/security/key_management/vault_key_manager.dart';
import 'package:safekeep/security/security_exceptions.dart';

/// End-to-end exercises of the whole security module wired together:
/// KDF -> KeyManager -> BiometricGate -> EncryptionService.
///
/// The unit suites prove each piece in isolation; these prove the pieces
/// compose into the flows the app will actually perform.

class _FakeStore implements SecureKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _FakeBiometricGate implements BiometricGate {
  bool succeeds = true;
  int authenticateCalls = 0;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> authenticate({required String reason}) async {
    authenticateCalls++;
    return succeeds;
  }
}

/// Cheap cost factors; production values are pinned in
/// key_derivation_test.dart.
const _fastParams = KdfParameters(
  memoryKib: 64,
  iterations: 1,
  parallelism: 1,
  keyLengthBytes: 32,
);

const _passphrase = 'correct horse battery staple';
const _keyId = 'master';
const _docId = 'doc-1';

Uint8List _document(int length, {int seed = 7}) {
  final random = Random(seed);
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = random.nextInt(256);
  }
  return bytes;
}

void main() {
  late _FakeStore store;
  late _FakeBiometricGate gate;
  late VaultKeyManager keyManager;
  late AesGcmEncryptionService encryption;

  setUp(() {
    store = _FakeStore();
    gate = _FakeBiometricGate();
    keyManager = VaultKeyManager(
      store: store,
      biometricGate: gate,
      setupParameters: _fastParams,
    );
    encryption = AesGcmEncryptionService(keySource: keyManager);
  });

  group('full document lifecycle', () {
    test(
      'set up -> encrypt -> lock -> biometric unlock -> decrypt',
      () async {
        // This is the flow the app performs every day.
        final original = _document(64 * 1024);

        // 1. First run: the user chooses a passphrase.
        await keyManager.setUpVault(passphrase: _passphrase);
        expect(keyManager.isUnlocked, isTrue);

        // 2. A document is imported and encrypted.
        final blob = await encryption.encrypt(
          original,
          keyId: _keyId,
          documentId: _docId,
        );
        expect(blob.length, original.length + 29);

        // 3. The app is backgrounded long enough to auto-lock.
        keyManager.lock();
        expect(keyManager.isUnlocked, isFalse);

        // 4. While locked, the document cannot be read at all.
        await expectLater(
          () => encryption.decrypt(blob, keyId: _keyId, documentId: _docId),
          throwsA(isA<VaultLockedException>()),
        );

        // 5. The user returns and passes the biometric prompt.
        gate.succeeds = true;
        expect(await keyManager.unlockWithBiometrics(), isTrue);
        expect(gate.authenticateCalls, 1);

        // 6. The document decrypts to exactly the original bytes.
        expect(
          await encryption.decrypt(blob, keyId: _keyId, documentId: _docId),
          original,
        );
      },
    );

    test('set up -> encrypt -> lock -> passphrase unlock -> decrypt', () async {
      final original = _document(4096);

      await keyManager.setUpVault(passphrase: _passphrase);
      final blob = await encryption.encrypt(
        original,
        keyId: _keyId,
        documentId: _docId,
      );

      keyManager.lock();
      expect(await keyManager.unlockWithPassphrase(_passphrase), isTrue);

      expect(
        await encryption.decrypt(blob, keyId: _keyId, documentId: _docId),
        original,
      );
    });

    test('multiple documents survive a lock/unlock cycle', () async {
      await keyManager.setUpVault(passphrase: _passphrase);

      final documents = [
        _document(128, seed: 1),
        _document(5000, seed: 2),
        _document(100000, seed: 3),
      ];
      final blobs = <Uint8List>[
        for (final doc in documents)
          await encryption.encrypt(doc, keyId: _keyId, documentId: _docId),
      ];

      keyManager.lock();
      await keyManager.unlockWithPassphrase(_passphrase);

      for (var i = 0; i < documents.length; i++) {
        expect(
          await encryption.decrypt(blobs[i], keyId: _keyId, documentId: _docId),
          documents[i],
        );
      }
    });
  });

  group('locked vault denies access', () {
    setUp(() => keyManager.setUpVault(passphrase: _passphrase));

    test('encrypting is impossible while locked', () async {
      keyManager.lock();

      await expectLater(
        () => encryption.encrypt(
          _document(64),
          keyId: _keyId,
          documentId: _docId,
        ),
        throwsA(isA<VaultLockedException>()),
      );
    });

    test('a cancelled biometric prompt leaves documents unreadable', () async {
      final blob = await encryption.encrypt(
        _document(256),
        keyId: _keyId,
        documentId: _docId,
      );
      keyManager.lock();

      gate.succeeds = false;
      expect(await keyManager.unlockWithBiometrics(), isFalse);

      await expectLater(
        () => encryption.decrypt(blob, keyId: _keyId, documentId: _docId),
        throwsA(isA<VaultLockedException>()),
      );
    });

    test('a wrong passphrase leaves documents unreadable', () async {
      final blob = await encryption.encrypt(
        _document(256),
        keyId: _keyId,
        documentId: _docId,
      );
      keyManager.lock();

      expect(await keyManager.unlockWithPassphrase('wrong'), isFalse);

      await expectLater(
        () => encryption.decrypt(blob, keyId: _keyId, documentId: _docId),
        throwsA(isA<VaultLockedException>()),
      );
    });

    test('auto-lock after backgrounding makes documents unreadable', () async {
      final blob = await encryption.encrypt(
        _document(256),
        keyId: _keyId,
        documentId: _docId,
      );

      // Drive the controller directly rather than waiting on a timer.
      AutoLockController(keyManager: keyManager).lockNow();

      await expectLater(
        () => encryption.decrypt(blob, keyId: _keyId, documentId: _docId),
        throwsA(isA<VaultLockedException>()),
      );
    });
  });

  group('cross-device restore', () {
    test('the same passphrase on a fresh device reads the old blobs', () async {
      // Device A creates a vault and encrypts a document.
      await keyManager.setUpVault(passphrase: _passphrase);
      final original = _document(2048);
      final blob = await encryption.encrypt(
        original,
        keyId: _keyId,
        documentId: _docId,
      );

      // Device B restores a backup. It receives the salt, KDF
      // parameters, and verifier — all non-secret, which is exactly why
      // they can travel alongside the encrypted blobs — but NOT the
      // encryption key, which never leaves device A's Keystore. The key
      // must be re-derived from the passphrase, which is the whole point
      // of a deterministic KDF.
      final deviceBStore = _FakeStore();
      deviceBStore.values.addAll({
        'safekeep.v1.salt': store.values['safekeep.v1.salt']!,
        'safekeep.v1.kdf_params': store.values['safekeep.v1.kdf_params']!,
        'safekeep.v1.verifier': store.values['safekeep.v1.verifier']!,
      });

      final deviceBManager = VaultKeyManager(
        store: deviceBStore,
        biometricGate: _FakeBiometricGate(),
        setupParameters: _fastParams,
      );
      final deviceBEncryption = AesGcmEncryptionService(
        keySource: deviceBManager,
      );

      expect(await deviceBManager.unlockWithPassphrase(_passphrase), isTrue);
      expect(
        await deviceBEncryption.decrypt(
          blob,
          keyId: _keyId,
          documentId: _docId,
        ),
        original,
        reason: 'documents must survive a move to a new device',
      );
    });

    test(
      'a wrong passphrase on the new device cannot read the blobs',
      () async {
        await keyManager.setUpVault(passphrase: _passphrase);
        final blob = await encryption.encrypt(
          _document(512),
          keyId: _keyId,
          documentId: _docId,
        );

        final deviceBStore = _FakeStore();
        deviceBStore.values.addAll({
          'safekeep.v1.salt': store.values['safekeep.v1.salt']!,
          'safekeep.v1.kdf_params': store.values['safekeep.v1.kdf_params']!,
          'safekeep.v1.verifier': store.values['safekeep.v1.verifier']!,
        });

        final deviceBManager = VaultKeyManager(
          store: deviceBStore,
          biometricGate: _FakeBiometricGate(),
          setupParameters: _fastParams,
        );

        expect(await deviceBManager.verifyPassphrase('not it'), isFalse);
        expect(await deviceBManager.unlockWithPassphrase('not it'), isFalse);

        await expectLater(
          () => AesGcmEncryptionService(
            keySource: deviceBManager,
          ).decrypt(blob, keyId: _keyId, documentId: _docId),
          throwsA(isA<VaultLockedException>()),
        );
      },
    );
  });

  group('crypto-erase', () {
    test(
      'deleting the vault makes existing blobs permanently unreadable',
      () async {
        await keyManager.setUpVault(passphrase: _passphrase);
        final blob = await encryption.encrypt(
          _document(1024),
          keyId: _keyId,
          documentId: _docId,
        );

        await keyManager.deleteVault();

        // Even the correct passphrase cannot bring it back: the salt is
        // gone, so the key cannot be re-derived.
        await expectLater(
          () => keyManager.unlockWithPassphrase(_passphrase),
          throwsA(isA<VaultNotInitializedException>()),
        );
        await expectLater(
          () => encryption.decrypt(blob, keyId: _keyId, documentId: _docId),
          throwsA(isA<VaultLockedException>()),
        );
      },
    );
  });

  group('no plaintext or key material leaks into storage', () {
    test(
      'stored values contain neither the passphrase nor the plaintext',
      () async {
        await keyManager.setUpVault(passphrase: _passphrase);

        const secretText = 'MY-SECRET-PASSPORT-NUMBER-X1234567';
        await encryption.encrypt(
          Uint8List.fromList(utf8.encode(secretText)),
          keyId: _keyId,
          documentId: _docId,
        );

        for (final value in store.values.values) {
          expect(value, isNot(contains(_passphrase)));
          expect(value, isNot(contains(secretText)));
          expect(value, isNot(contains(base64Encode(utf8.encode(secretText)))));
        }
      },
    );

    test('an encrypted blob does not contain the plaintext', () async {
      await keyManager.setUpVault(passphrase: _passphrase);

      const secretText = 'MY-SECRET-PASSPORT-NUMBER-X1234567';
      final plaintext = Uint8List.fromList(utf8.encode(secretText));

      final blob = await encryption.encrypt(
        plaintext,
        keyId: _keyId,
        documentId: _docId,
      );

      expect(
        utf8.decode(blob, allowMalformed: true),
        isNot(contains(secretText)),
      );
    });
  });
}
