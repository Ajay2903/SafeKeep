import 'dart:typed_data';

/// Storage of encrypted document blobs on disk.
///
/// Backed by `path_provider` in the real implementation, writing into the
/// app's private storage directory. Callers are expected to pass already
/// -encrypted bytes (from `security/encryption`) — this class never sees
/// plaintext document contents.
// TODO(phase1): implement using path_provider; decide on a directory
// layout and filename scheme alongside the first feature that needs it.
abstract interface class DocumentFileStorage {
  Future<void> write(String documentId, Uint8List encryptedBytes);

  Future<Uint8List> read(String documentId);

  Future<void> delete(String documentId);
}
