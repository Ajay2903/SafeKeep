import 'dart:convert';
import 'dart:typed_data';

import 'package:safekeep/core/logging/app_logger.dart';
import 'package:safekeep/security/auth/biometric_gate.dart';
import 'package:safekeep/security/key_management/kdf_parameters.dart';
import 'package:safekeep/security/key_management/key_derivation.dart';
import 'package:safekeep/security/key_management/key_manager.dart';
import 'package:safekeep/security/key_management/secure_key_value_store.dart';
import 'package:safekeep/security/security_exceptions.dart';

/// Default [KeyManager], backed by platform secure storage.
///
/// # What is persisted, and what is not
///
/// | Item              | Secret? | Why it is stored                    |
/// |-------------------|---------|-------------------------------------|
/// | salt              | no      | needed to re-derive the key         |
/// | KDF parameters    | no      | old vaults must keep deriving with  |
/// |                   |         | the params they were created under  |
/// | verifier          | no*     | checks a passphrase without a doc   |
/// | encryption key    | **yes** | enables biometric unlock            |
///
/// \* The verifier is not the key and reveals nothing about it (see
/// `KeyDerivation` for the HKDF domain separation), but it does let an
/// offline attacker *test* passphrase guesses. That is unavoidable for any
/// offline vault and is what the Argon2id cost defends against.
///
/// **The passphrase itself is never stored, in any form.**
///
/// # Storing the key: the deliberate tradeoff
///
/// The derived encryption key is written to secure storage (Android
/// Keystore / iOS Keychain) so that biometric unlock does not require
/// re-entering the passphrase. The consequence, stated plainly: after
/// setup, the passphrase is no longer the only thing standing between an
/// attacker and the data on *this device* — hardware-backed storage plus
/// the biometric gate are. An attacker who fully compromises the OS and
/// defeats biometrics could extract the key without ever knowing the
/// passphrase. This is the same tradeoff mainstream password managers
/// make for usability, and it does not weaken blobs backed up elsewhere,
/// which remain protected by the passphrase alone.
///
/// # Logging
///
/// Every log line here records an *event*, never a value. No key, no
/// passphrase, no salt, no verifier is ever passed to [AppLogger].
class VaultKeyManager implements KeyManager {
  /// [setupParameters] are the KDF cost factors used when *creating* a
  /// vault. Existing vaults always re-derive with the parameters stored at
  /// their own creation time, never with this value — see
  /// [_deriveFromStoredParameters]. Injectable so tests can use cheap
  /// factors; production leaves it at the reviewed [KdfParameters.current].
  VaultKeyManager({
    required SecureKeyValueStore store,
    required BiometricGate biometricGate,
    KeyDerivation keyDerivation = const KeyDerivation(),
    KdfParameters setupParameters = KdfParameters.current,
  }) : this._(store, biometricGate, keyDerivation, setupParameters);

  VaultKeyManager._(
    this._store,
    this._biometricGate,
    this._keyDerivation,
    this._setupParameters,
  );

  /// Storage keys. Namespaced and versioned so a future format change can
  /// coexist with, and migrate from, the current one.
  static const String _saltKey = 'safekeep.v1.salt';
  static const String _paramsKey = 'safekeep.v1.kdf_params';
  static const String _verifierKey = 'safekeep.v1.verifier';
  static const String _encryptionKeyKey = 'safekeep.v1.encryption_key';

  final SecureKeyValueStore _store;
  final BiometricGate _biometricGate;
  final KeyDerivation _keyDerivation;
  final KdfParameters _setupParameters;

  /// The session key. Non-null exactly when the vault is unlocked.
  Uint8List? _sessionKey;

  @override
  bool get isUnlocked => _sessionKey != null;

  @override
  Future<bool> isInitialized() async =>
      await _store.read(_encryptionKeyKey) != null;

  @override
  Future<void> setUpVault({required String passphrase}) async {
    if (await isInitialized()) {
      throw const VaultAlreadyInitializedException();
    }

    final salt = KeyDerivation.generateSalt();
    final parameters = _setupParameters;

    final keys = await _keyDerivation.deriveKeys(
      passphrase: passphrase,
      salt: salt,
      parameters: parameters,
    );

    // Write the non-secret material first. If the process dies midway,
    // isInitialized() still reports false (it keys off the encryption
    // key), so setup can be retried cleanly rather than leaving a vault
    // that looks real but has no key.
    await _store.write(_saltKey, base64Encode(salt));
    await _store.write(_paramsKey, parameters.toJson());
    await _store.write(_verifierKey, base64Encode(keys.verifier));
    await _store.write(_encryptionKeyKey, base64Encode(keys.encryptionKey));

    // Setup implies the user just proved knowledge of the passphrase.
    _sessionKey = Uint8List.fromList(keys.encryptionKey);
    keys.destroy();

    AppLogger.instance.info('Vault created');
  }

  @override
  Future<bool> verifyPassphrase(String passphrase) async {
    final keys = await _deriveFromStoredParameters(passphrase);
    try {
      return _constantTimeEquals(keys.verifier, await _storedVerifier());
    } finally {
      keys.destroy();
    }
  }

  @override
  Future<bool> unlockWithPassphrase(String passphrase) async {
    final keys = await _deriveFromStoredParameters(passphrase);
    try {
      if (!_constantTimeEquals(keys.verifier, await _storedVerifier())) {
        AppLogger.instance.info('Vault unlock rejected');
        return false;
      }
      // Use the freshly derived key rather than reading storage: it is
      // the same value, and this path stays correct even if the stored
      // copy is ever removed.
      _sessionKey = Uint8List.fromList(keys.encryptionKey);
      AppLogger.instance.info('Vault unlocked with passphrase');
      return true;
    } finally {
      keys.destroy();
    }
  }

  @override
  Future<bool> unlockWithBiometrics() async {
    if (!await isInitialized()) {
      throw const VaultNotInitializedException();
    }

    // The gate must pass *before* the key is read out of secure storage.
    final authenticated = await _biometricGate.authenticate(
      reason: 'Unlock your SafeKeep vault',
    );
    if (!authenticated) {
      AppLogger.instance.info('Vault unlock cancelled at biometric gate');
      return false;
    }

    final stored = await _store.read(_encryptionKeyKey);
    if (stored == null) {
      throw const VaultNotInitializedException();
    }

    _sessionKey = Uint8List.fromList(base64Decode(stored));
    AppLogger.instance.info('Vault unlocked with biometrics');
    return true;
  }

  @override
  Future<Uint8List> encryptionKeyFor(String keyId) async {
    final key = _sessionKey;
    if (key == null) {
      throw const VaultLockedException();
    }
    // A copy, so a caller cannot retain a view that survives lock() —
    // zeroing our buffer would otherwise silently corrupt their key.
    return Uint8List.fromList(key);
  }

  @override
  void lock() {
    final key = _sessionKey;
    if (key == null) return;

    // Overwrite before dropping the reference. Best-effort: Dart cannot
    // guarantee the GC has not already copied these bytes, but this
    // meaningfully shortens the window in which the key sits in the heap.
    key.fillRange(0, key.length, 0);
    _sessionKey = null;

    AppLogger.instance.info('Vault locked');
  }

  @override
  Future<void> deleteVault() async {
    lock();
    await _store.delete(_encryptionKeyKey);
    await _store.delete(_verifierKey);
    await _store.delete(_saltKey);
    await _store.delete(_paramsKey);

    AppLogger.instance.warning(
      'Vault deleted; encrypted data is now '
      'unrecoverable',
    );
  }

  /// Derives key material using the salt and parameters this vault was
  /// created with — never the current defaults, which may have changed.
  Future<DerivedKeys> _deriveFromStoredParameters(String passphrase) async {
    final encodedSalt = await _store.read(_saltKey);
    final encodedParams = await _store.read(_paramsKey);
    if (encodedSalt == null || encodedParams == null) {
      throw const VaultNotInitializedException();
    }

    return _keyDerivation.deriveKeys(
      passphrase: passphrase,
      salt: Uint8List.fromList(base64Decode(encodedSalt)),
      parameters: KdfParameters.fromJson(encodedParams),
    );
  }

  Future<Uint8List> _storedVerifier() async {
    final encoded = await _store.read(_verifierKey);
    if (encoded == null) {
      throw const VaultNotInitializedException();
    }
    return Uint8List.fromList(base64Decode(encoded));
  }
}

/// Compares two byte sequences without leaking where they first differ.
///
/// A plain `==` or an early `return false` inside the loop would finish
/// sooner the earlier a mismatch occurs. An attacker able to time
/// [VaultKeyManager.verifyPassphrase] could then recover the verifier one
/// byte at a time instead of guessing it whole. Every byte is compared and
/// the differences accumulated, so the running time depends only on the
/// length.
///
/// The length check itself may short-circuit: lengths are fixed by the
/// format and are not secret.
bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;

  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}
