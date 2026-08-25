import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:safekeep/security/key_management/secure_key_value_store.dart';

/// [SecureKeyValueStore] backed by Android Keystore / iOS Keychain.
///
/// Deliberately a thin pass-through with no logic of its own: it cannot be
/// unit-tested (platform channels are unavailable under `flutter test`),
/// so anything non-trivial living here would be untested code on the most
/// security-critical path in the app. All lifecycle logic sits in
/// `VaultKeyManager`, which is tested exhaustively against a fake.
///
/// # Platform options and why they are set explicitly
///
/// **Android** — the default `AndroidOptions` already wraps an AES-GCM
/// storage key with an RSA-OAEP key held in the Keystore. `resetOnError`
/// is turned **off**: its default (`true`) silently wipes stored values
/// when decryption fails. For a preferences cache that is a reasonable
/// self-heal, but here the stored value *is* the vault key — discarding it
/// would destroy the user's documents with no warning and no recovery.
/// Failing loudly is the only acceptable behaviour.
///
/// **iOS/macOS** — `first_unlock_this_device` means the item is readable
/// only after the device has been unlocked once since boot, and is
/// excluded from iCloud Keychain sync and encrypted backups. The vault key
/// must not silently propagate to the user's other devices: SafeKeep's
/// model is that a new device is set up by entering the passphrase, not by
/// having the key handed to it by a backup.
// NOTE: needs on-device verification; there is no way to exercise a real
// Keystore/Keychain from a unit test. See ARCHITECTURE.md's manual
// checklist.
class FlutterSecureStorageStore implements SecureKeyValueStore {
  const FlutterSecureStorageStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const AndroidOptions _androidOptions = AndroidOptions(
    resetOnError: false,
  );

  static const IOSOptions _appleOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(
    key: key,
    aOptions: _androidOptions,
    iOptions: _appleOptions,
    mOptions: _appleOptions,
  );

  @override
  Future<void> write(String key, String value) => _storage.write(
    key: key,
    value: value,
    aOptions: _androidOptions,
    iOptions: _appleOptions,
    mOptions: _appleOptions,
  );

  @override
  Future<void> delete(String key) => _storage.delete(
    key: key,
    aOptions: _androidOptions,
    iOptions: _appleOptions,
    mOptions: _appleOptions,
  );
}
