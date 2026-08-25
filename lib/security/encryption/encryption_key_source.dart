import 'dart:typed_data';

// Imported for the [VaultLockedException] doc reference below.
import 'package:safekeep/security/security_exceptions.dart';

/// Supplies the encryption key for a given `keyId`.
///
/// Deliberately narrow. `AesGcmEncryptionService` needs exactly one thing
/// — "give me the key for this id" — and nothing about vault setup,
/// unlocking, or biometrics. Keeping that the whole contract means the
/// cipher can be tested against a two-line fake, and means the encryption
/// code has no way to reach vault lifecycle operations it has no business
/// calling.
///
/// `KeyManager` implements this. Implementations are expected to throw
/// [VaultLockedException] rather than return a key while the vault is
/// locked.
// A one-member interface is intentional here: this is a dependency-
// injection seam implemented by KeyManager and faked in tests, not a
// function that happens to be wrapped in a class.
// ignore: one_member_abstracts
abstract interface class EncryptionKeySource {
  /// Returns the 32-byte AES-256 key for [keyId].
  ///
  /// The returned bytes must never be logged, persisted in plaintext, or
  /// passed anywhere other than the cipher.
  Future<Uint8List> encryptionKeyFor(String keyId);
}
