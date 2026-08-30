import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:safekeep/security/encryption/encrypted_blob.dart';
import 'package:safekeep/security/encryption/encryption_key_source.dart';
import 'package:safekeep/security/encryption/encryption_service.dart';
import 'package:safekeep/security/security_exceptions.dart';

/// AES-256-GCM implementation of [EncryptionService].
///
/// # Why AES-256-GCM
///
/// GCM is an AEAD mode: it produces an authentication tag alongside the
/// ciphertext, so decryption *detects* modification instead of returning
/// attacker-controlled plaintext. That property is essential here, because
/// SafeKeep blobs are expected to live in the user's own cloud storage
/// where they can be modified by anyone who compromises that account. A
/// non-authenticated mode such as AES-CBC would decrypt tampered data
/// silently. 256-bit keys match the KDF output.
///
/// # Nonce handling
///
/// Every call to [encrypt] generates a fresh 96-bit nonce from
/// `Random.secure` (via `package:cryptography`'s `newNonce()`); nonces are
/// never reused, never derived from the plaintext, and never taken from a
/// counter. Reusing a nonce under one key in GCM is catastrophic — it
/// leaks the XOR of both plaintexts and enables tag forgery — and a
/// persisted counter cannot be trusted across app reinstalls, crashes, or
/// device restores. See [EncryptedBlob] for the collision-budget analysis.
///
/// # Performance note
///
/// `package:cryptography`'s AES-GCM is pure Dart, measured at roughly
/// 20 MB/s AOT on desktop, so a 10 MB document takes on the order of a
/// second or two on a phone and will block the calling isolate while it
/// runs. This is acceptable for the current scope but should be revisited
/// when document import/export UI lands.
// TODO(phase2): before shipping large-file UI, either move encrypt/decrypt
// onto a background isolate or adopt package:cryptography_flutter, which
// swaps in platform-native AES-GCM (~10x faster). Neither changes the
// stored blob format, so both are drop-in and need no data migration.
class AesGcmEncryptionService implements EncryptionService {
  const AesGcmEncryptionService({required EncryptionKeySource keySource})
    : this._(keySource);

  const AesGcmEncryptionService._(this._keySource);

  /// Required AES-256 key length, in bytes.
  static const int keyLength = 32;

  final EncryptionKeySource _keySource;

  /// Shared algorithm instance. Stateless and safe to reuse; the nonce is
  /// generated per call, not held here.
  static final AesGcm _algorithm = AesGcm.with256bits();

  @override
  Future<Uint8List> encrypt(
    Uint8List plaintext, {
    required String keyId,
    required String documentId,
  }) async {
    final secretKey = await _secretKeyFor(keyId);

    // No explicit nonce argument: the library generates a fresh one from
    // Random.secure for every call, which is exactly what we want.
    final box = await _algorithm.encrypt(
      plaintext,
      secretKey: secretKey,
      aad: EncryptedBlob.associatedData(documentId: documentId),
    );

    return EncryptedBlob.pack(
      nonce: box.nonce,
      tag: box.mac.bytes,
      ciphertext: box.cipherText,
    );
  }

  @override
  Future<Uint8List> decrypt(
    Uint8List ciphertext, {
    required String keyId,
    required String documentId,
  }) async {
    // Parse (and therefore validate framing) before touching key material.
    final parsed = EncryptedBlob.unpack(ciphertext);
    final secretKey = await _secretKeyFor(keyId);

    final box = SecretBox(
      parsed.ciphertext,
      nonce: parsed.nonce,
      mac: Mac(parsed.tag),
    );

    try {
      final plaintext = await _algorithm.decrypt(
        box,
        secretKey: secretKey,
        aad: EncryptedBlob.associatedData(documentId: documentId),
      );
      return Uint8List.fromList(plaintext);
    } on SecretBoxAuthenticationError {
      // The tag did not verify. Translate into our own exception rather
      // than leaking a third-party type, and deliberately do not say
      // whether the cause was tampering, corruption, a wrong key, or a
      // mismatched documentId.
      //
      // Nothing is logged here: an error path around decryption is exactly
      // where plaintext or key material would leak into logs.
      throw const DecryptionAuthenticationException();
    }
  }

  /// Fetches the key for [keyId] and checks its length.
  ///
  /// A short key would otherwise be accepted by the cipher and silently
  /// produce a weaker-than-intended encryption, so this fails loudly.
  Future<SecretKey> _secretKeyFor(String keyId) async {
    final keyBytes = await _keySource.encryptionKeyFor(keyId);
    if (keyBytes.length != keyLength) {
      throw ArgumentError.value(
        keyBytes.length,
        'key',
        'AES-256 requires a $keyLength-byte key',
      );
    }
    return SecretKey(keyBytes);
  }
}
