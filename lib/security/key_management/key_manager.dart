/// Generation, retrieval, and deletion of the app's master encryption key.
///
/// The real implementation (a later phase, not Phase 0) is expected to
/// generate a random key on first launch, persist it via
/// `flutter_secure_storage` (Android Keystore / iOS Keychain), and never
/// hold the key in memory longer than a single encrypt/decrypt operation
/// requires. This interface exists now so that `EncryptionService` and
/// callers can be written and tested against it before that implementation
/// lands.
///
/// Until a real implementation lands, do not instantiate a concrete
/// implementation of this interface outside of tests.
// TODO(phase1): implement using flutter_secure_storage.
abstract interface class KeyManager {
  /// Returns the key material for [keyId], generating and persisting it on
  /// first use if it doesn't exist yet.
  ///
  /// The returned bytes must never be logged or passed to anything other
  /// than an `EncryptionService`.
  Future<List<int>> getOrCreateKey(String keyId);

  /// Permanently deletes the key material for [keyId]. Any ciphertext
  /// encrypted under this key becomes unrecoverable — this is the
  /// mechanism for a cryptographic-erase style "delete everything".
  Future<void> deleteKey(String keyId);
}
