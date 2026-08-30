import 'dart:math';

/// Generates identifiers for documents.
///
/// The identifier does triple duty, which is why it is random rather than
/// sequential:
///
/// 1. It is the primary key of the metadata row.
/// 2. It names the encrypted blob on disk.
/// 3. It is bound into the blob's AES-GCM associated data, so a blob only
///    authenticates for the document it belongs to.
///
/// A collision would therefore overwrite another document's blob *and*
/// make the survivor's ciphertext appear valid under the wrong record —
/// so the id is drawn from the platform CSPRNG at 128 bits, where
/// collisions are negligible far beyond any plausible vault size.
///
/// Sequential ids were rejected: they leak how many documents exist and
/// the order they were added, which is metadata worth not having, and
/// they would collide outright when two devices add documents offline
/// before syncing.
abstract final class DocumentId {
  /// Length in bytes of the underlying random value.
  static const int lengthBytes = 16;

  /// Returns a fresh 32-character lowercase hex identifier.
  ///
  /// Hex rather than base64 so the value is safe to use directly as a
  /// filename on every platform, with no escaping and no case-sensitivity
  /// surprises.
  static String generate() {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < lengthBytes; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// The blob filename for [id].
  static String blobFileName(String id) => '$id.blob';
}
