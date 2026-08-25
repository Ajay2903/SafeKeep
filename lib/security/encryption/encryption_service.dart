import 'dart:typed_data';

/// Authenticated encryption/decryption of arbitrary bytes.
///
/// The real implementation (a later phase, not Phase 0) is expected to use
/// the `cryptography` package with AES-256-GCM: a 96-bit random nonce per
/// call, the returned MAC verified on every decrypt, and the key supplied
/// by a `KeyManager` rather than held by this class. This interface exists
/// now so that document-import/export code can be written and tested
/// against it before that implementation lands.
///
/// Until a real implementation lands, do not instantiate a concrete
/// implementation of this interface outside of tests.
// TODO(phase1): implement using package:cryptography (AES-GCM).
abstract interface class EncryptionService {
  /// Encrypts [plaintext] under [keyId], returning ciphertext with its
  /// nonce and authentication tag embedded so [decrypt] is self-contained.
  ///
  /// [plaintext] must never be logged, including on error paths.
  Future<Uint8List> encrypt(Uint8List plaintext, {required String keyId});

  /// Decrypts data previously produced by [encrypt]. Throws if the
  /// authentication tag doesn't verify — callers must treat that as
  /// tampering or corruption, never as "try again".
  Future<Uint8List> decrypt(Uint8List ciphertext, {required String keyId});
}
