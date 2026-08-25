import 'dart:typed_data';

import 'package:safekeep/security/security_exceptions.dart';

/// On-disk / on-the-wire format for one encrypted document.
///
/// # Byte layout
///
/// ```text
/// Offset  Length  Field
/// ------  ------  ---------------------------------------------------
///      0       1  format version (currently 0x01)
///      1      12  nonce  — 96-bit, freshly random for every encryption
///     13      16  tag    — 128-bit AES-GCM authentication tag
///     29       N  ciphertext — exactly as long as the plaintext
/// ```
///
/// Total size is always `29 + plaintextLength` bytes.
///
/// # Why these sizes
///
/// * **Version byte.** One byte bought now means the algorithm, KDF, or
///   layout can change later without ever having to guess how an existing
///   blob was produced. Without it, a future format change would be
///   ambiguous and therefore unsafe.
/// * **12-byte nonce.** GCM's standard nonce length. A 96-bit nonce is used
///   by GCM *directly*; any other length is first compressed through GHASH,
///   which is slower and adds a needless subtlety. Freshly random per call,
///   never a counter — a counter would need reliable persistent state that
///   a mobile app (restores, crashes, reinstalls) cannot guarantee, and a
///   repeated GCM nonce under the same key is catastrophic.
/// * **16-byte tag.** The full 128-bit GCM tag. Truncating it is permitted
///   by the spec but only weakens forgery resistance for a 15-byte saving.
///
/// # Nonce collision budget
///
/// With random 96-bit nonces the birthday bound gives a negligible
/// collision probability below roughly 2^32 encryptions **under one key**.
/// A personal document vault is many orders of magnitude below that, so
/// random nonces are safe here. If SafeKeep ever re-encrypts at machine
/// scale under a single long-lived key, revisit this.
///
/// # Layout note
///
/// The tag is stored *before* the ciphertext, at a fixed offset, so the
/// header is a constant 29 bytes and parsing never depends on the total
/// length. (`package:cryptography` keeps the tag as a separate `Mac`
/// rather than appending it, so nothing here is fighting the library.)
abstract final class EncryptedBlob {
  /// Current format version written by [pack].
  static const int version = 0x01;

  static const int versionLength = 1;
  static const int nonceLength = 12;
  static const int tagLength = 16;

  /// Fixed header size: version + nonce + tag.
  static const int headerLength = versionLength + nonceLength + tagLength;

  static const int _nonceOffset = versionLength;
  static const int _tagOffset = _nonceOffset + nonceLength;
  static const int _ciphertextOffset = _tagOffset + tagLength;

  /// Assembles the stored representation from its parts.
  ///
  /// Throws [ArgumentError] on a wrong-sized nonce or tag — that would be
  /// a programming error inside this module, not attacker-supplied input.
  static Uint8List pack({
    required List<int> nonce,
    required List<int> tag,
    required List<int> ciphertext,
  }) {
    if (nonce.length != nonceLength) {
      throw ArgumentError.value(
        nonce.length,
        'nonce',
        'nonce must be exactly $nonceLength bytes',
      );
    }
    if (tag.length != tagLength) {
      throw ArgumentError.value(
        tag.length,
        'tag',
        'tag must be exactly $tagLength bytes',
      );
    }

    final out = Uint8List(headerLength + ciphertext.length)
      ..[0] = version
      ..setRange(_nonceOffset, _tagOffset, nonce)
      ..setRange(_tagOffset, _ciphertextOffset, tag)
      ..setRange(
        _ciphertextOffset,
        headerLength + ciphertext.length,
        ciphertext,
      );
    return out;
  }

  /// Parses a stored blob back into its parts.
  ///
  /// This runs on untrusted input (a file on disk, or a blob restored from
  /// the user's cloud backup), so every length and the version byte are
  /// validated before anything is handed to the cipher.
  ///
  /// Throws [MalformedCiphertextException] if the input is not a
  /// well-formed blob. Note this says nothing about authenticity — the tag
  /// is only checked later, during decryption.
  static ParsedBlob unpack(Uint8List blob) {
    if (blob.length < headerLength) {
      throw MalformedCiphertextException(
        'Encrypted blob is ${blob.length} bytes, shorter than the '
        '$headerLength-byte header.',
      );
    }
    final blobVersion = blob[0];
    if (blobVersion != version) {
      throw MalformedCiphertextException(
        'Unsupported encrypted blob format version $blobVersion; this '
        'build understands version $version.',
      );
    }

    return ParsedBlob(
      nonce: Uint8List.sublistView(blob, _nonceOffset, _tagOffset),
      tag: Uint8List.sublistView(blob, _tagOffset, _ciphertextOffset),
      ciphertext: Uint8List.sublistView(blob, _ciphertextOffset),
    );
  }
}

/// The three components of a parsed [EncryptedBlob].
///
/// These are views onto the original blob's buffer, not copies.
class ParsedBlob {
  const ParsedBlob({
    required this.nonce,
    required this.tag,
    required this.ciphertext,
  });

  final Uint8List nonce;
  final Uint8List tag;
  final Uint8List ciphertext;
}
