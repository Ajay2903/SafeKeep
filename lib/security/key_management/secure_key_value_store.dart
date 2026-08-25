/// Minimal key/value store backed by platform secure storage.
///
/// This seam exists for one practical reason: `flutter_secure_storage`
/// talks over a platform channel and cannot run under `flutter test`, so
/// depending on it directly would make the entire vault lifecycle
/// untestable. Everything in `KeyManager` is written against this
/// interface, so the lifecycle can be exercised exhaustively against an
/// in-memory fake while the real implementation stays a thin, auditable
/// wrapper.
///
/// Values are strings because that is what the underlying platform APIs
/// (Android Keystore-backed EncryptedSharedPreferences, iOS Keychain)
/// store. Binary key material is base64-encoded by the caller.
abstract interface class SecureKeyValueStore {
  /// Returns the stored value for [key], or `null` if absent.
  Future<String?> read(String key);

  /// Stores [value] under [key], replacing any existing value.
  Future<void> write(String key, String value);

  /// Removes [key]. Succeeds even if the key was not present.
  Future<void> delete(String key);
}
