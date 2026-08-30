import 'dart:convert';
import 'dart:typed_data';

import 'package:safekeep/security/security_exceptions.dart';

/// On-disk / on-the-wire format for one encrypted document.
///
/// # Byte layout
///
/// ```text
/// Offset  Length  Field
/// ------  ------  ---------------------------------------------------
///      0       1  format version (currently 0x02)
///      1      12  nonce  — 96-bit, freshly random for every encryption
///     13      16  tag    — 128-bit AES-GCM authentication tag
///     29       N  ciphertext — exactly as long as the plaintext
/// ```
///
/// Total size is always `29 + plaintextLength` bytes.
///
/// The GCM tag additionally covers the associated data built by
/// [associatedData], which is **not** stored in the blob — it is
/// reconstructed at decryption time from the format version and the
/// document identifier the caller supplies. See that method for why.
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
  ///
  /// `0x01` was the pre-release format, which bound no associated data and
  /// is therefore not readable by this build. It is deliberately not
  /// supported: v1 blobs were vulnerable to the substitution attack that
  /// [associatedData] exists to prevent, so silently accepting them would
  /// reintroduce exactly the weakness the version bump closes.
  static const int version = 0x02;

  static const int versionLength = 1;
  static const int nonceLength = 12;
  static const int tagLength = 16;

  /// Fixed header size: version + nonce + tag.
  static const int headerLength = versionLength + nonceLength + tagLength;

  static const int _nonceOffset = versionLength;
  static const int _tagOffset = _nonceOffset + nonceLength;
  static const int _ciphertextOffset = _tagOffset + tagLength;

  /// Builds the AES-GCM associated data binding a blob to one document.
  ///
  /// # The attack this prevents
  ///
  /// Every document is encrypted under the same vault key. Without
  /// associated data, a blob is valid *anywhere*: an attacker who can
  /// write to storage (the user's own cloud backup being the realistic
  /// case) could replace document A's blob with document B's, and
  /// decryption would succeed with a perfectly valid tag. The app would
  /// then display the wrong document with no indication anything was
  /// wrong — a silent integrity failure, not a detected one.
  ///
  /// Binding the document identifier means a blob only authenticates
  /// under the identity it was encrypted for. Substitution now fails the
  /// tag check like any other tampering.
  ///
  /// # Encoding
  ///
  /// ```text
  ///  version (1 byte)
  ///  documentId length (4 bytes, big-endian uint32)
  ///  documentId (UTF-8, that many bytes)
  /// ```
  ///
  /// The length prefix makes the encoding unambiguous. With a single
  /// trailing variable-length field it would be safe without one today,
  /// but any future field appended after `documentId` would create
  /// collisions between different (version, id, extra) triples. Prefixing
  /// now costs four bytes of AAD — which is never stored — and removes
  /// that trap entirely.
  ///
  /// Including the version byte also authenticates it. It sits in the
  /// blob header, which GCM does not otherwise cover, so without this an
  /// attacker could flip it freely.
  ///
  /// This AAD is **not** stored: it is recomputed at decryption time from
  /// the version in the header and the document id supplied by the
  /// caller. A caller asking for the wrong document therefore gets an
  /// authentication failure rather than someone else's plaintext.
  static Uint8List associatedData({required String documentId}) {
    final idBytes = utf8.encode(documentId);
    final aad = Uint8List(versionLength + 4 + idBytes.length);
    aad[0] = version;
    ByteData.sublistView(
      aad,
      versionLength,
      versionLength + 4,
    ).setUint32(0, idBytes.length);
    aad.setRange(versionLength + 4, aad.length, idBytes);
    return aad;
  }

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
