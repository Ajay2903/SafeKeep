import 'dart:typed_data';

import 'package:safekeep/domain/models/document.dart';
import 'package:safekeep/domain/models/document_category.dart';

/// The vault's public surface: add, read, list, update, and delete
/// documents.
///
/// Implemented in the data layer, which composes encrypted file storage
/// with the metadata database. Presentation code depends on this
/// interface only, so it never touches the cipher, the filesystem, or
/// SQL directly.
///
/// Every method requires an unlocked vault and will surface a
/// `VaultLockedException` otherwise.
abstract interface class DocumentRepository {
  /// Encrypts [bytes], writes the blob, and records its metadata.
  ///
  /// Returns the created [Document]. The plaintext [bytes] are the
  /// caller's responsibility to discard; nothing here retains them.
  Future<Document> addDocument({
    required Uint8List bytes,
    required String title,
    required DocumentCategory category,
    required String mimeType,
    List<String> tags,
    String? notes,
    DateTime? expiresAt,
  });

  /// Reads and decrypts the document's bytes into memory.
  ///
  /// Throws if the record is missing, the blob is absent, or
  /// authentication fails — the last meaning the blob was tampered with,
  /// corrupted, or does not belong to this document.
  Future<Uint8List> openDocument(String id);

  /// All documents, metadata only — no blob is read or decrypted.
  Future<List<Document>> listDocuments();

  /// One document's metadata, or `null` if no such record exists.
  Future<Document?> getDocument(String id);

  /// Updates the editable metadata fields, bumping `version` and
  /// `modifiedAt`. The blob is untouched.
  Future<Document> updateDocument(Document document);

  /// Removes every document: all metadata rows, all blobs, and every
  /// scheduled reminder.
  ///
  /// Used by "delete all data". Deleting the vault key alone would make
  /// the blobs undecryptable, but they would still occupy storage and
  /// still be visible as files — a user who asks to erase everything
  /// means the files too.
  Future<void> deleteAllDocuments();

  /// Removes the metadata record and deletes the encrypted blob.
  ///
  /// Succeeds even if the blob is already missing, so a partially failed
  /// earlier delete can always be cleaned up.
  Future<void> deleteDocument(String id);
}
