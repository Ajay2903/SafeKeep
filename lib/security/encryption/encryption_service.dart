import 'dart:typed_data';

/// Authenticated encryption/decryption of arbitrary bytes.
///
/// Implemented by `AesGcmEncryptionService` using AES-256-GCM: a 96-bit
/// random nonce per call, the MAC verified on every decrypt, and the key
/// supplied by a `KeyManager` rather than held by this class.
///
/// # Deviation from the Phase 0 interface
///
/// The original signatures took only `keyId`. `documentId` was added
/// because every document is encrypted under the same vault key, which
/// made any blob valid in any position: an attacker able to write to
/// storage could substitute one document's blob for another and both
/// would authenticate. Binding the document identity as AES-GCM
/// associated data closes that, and doing so requires the identity to
/// reach the cipher — hence the extra parameter.
///
/// It is `required` rather than optional on purpose. A default would let
/// a call site silently opt out of the binding, which is precisely the
/// bug this closes.
abstract interface class EncryptionService {
  /// Encrypts [plaintext] for the document identified by [documentId],
  /// under the key identified by [keyId].
  ///
  /// The returned blob carries its own nonce and authentication tag, so
  /// [decrypt] needs nothing but the same [keyId] and [documentId].
  ///
  /// [plaintext] must never be logged, including on error paths.
  Future<Uint8List> encrypt(
    Uint8List plaintext, {
    required String keyId,
    required String documentId,
  });

  /// Decrypts data previously produced by [encrypt].
  ///
  /// [documentId] must match the value used to encrypt. Supplying a
  /// different one fails authentication exactly as tampering would —
  /// that is the substitution defence working, not a spurious error.
  ///
  /// Throws if the authentication tag doesn't verify. Callers must treat
  /// that as tampering or corruption, never as "try again".
  Future<Uint8List> decrypt(
    Uint8List ciphertext, {
    required String keyId,
    required String documentId,
  });
}
