import 'dart:typed_data';

import 'package:safekeep/core/logging/app_logger.dart';
import 'package:safekeep/data/data_exceptions.dart';
import 'package:safekeep/data/database/document_dao.dart';
import 'package:safekeep/data/document_id.dart';
import 'package:safekeep/data/storage/document_file_storage.dart';
import 'package:safekeep/domain/models/document.dart';
import 'package:safekeep/domain/models/document_category.dart';
import 'package:safekeep/domain/repositories/document_repository.dart';
import 'package:safekeep/security/encryption/encryption_service.dart';

/// The vault: encryption, blob storage, and metadata composed into one
/// surface.
///
/// This class owns the *ordering* of operations across those three
/// pieces, which is where a naive implementation loses data. Each method
/// documents why its steps run in the order they do.
///
/// # Logging
///
/// Only document identifiers and event names are logged — never titles,
/// notes, tags, or bytes. See `AppLogger` for the full rule.
class VaultDocumentRepository implements DocumentRepository {
  VaultDocumentRepository({
    required EncryptionService encryption,
    required DocumentFileStorage fileStorage,
    required DocumentDao dao,
    DateTime Function() clock = DateTime.now,
  }) : this._(encryption, fileStorage, dao, clock);

  VaultDocumentRepository._(
    this._encryption,
    this._fileStorage,
    this._dao,
    this._clock,
  );

  /// Identifier of the vault's single document-encryption key.
  ///
  /// Every document is encrypted under one key; per-document keys were
  /// considered and not implemented. Substitution between documents is
  /// prevented by binding the document id as associated data, not by
  /// separate keys.
  static const String encryptionKeyId = 'master';

  final EncryptionService _encryption;
  final DocumentFileStorage _fileStorage;
  final DocumentDao _dao;
  final DateTime Function() _clock;

  @override
  Future<Document> addDocument({
    required Uint8List bytes,
    required String title,
    required DocumentCategory category,
    List<String> tags = const [],
    String? notes,
    DateTime? expiresAt,
  }) async {
    final id = DocumentId.generate();
    final blobFileName = DocumentId.blobFileName(id);
    final now = _clock().toUtc();

    final blob = await _encryption.encrypt(
      bytes,
      keyId: encryptionKeyId,
      documentId: id,
    );

    final document = Document(
      id: id,
      title: title,
      category: category,
      tags: List.unmodifiable(tags),
      notes: notes,
      expiresAt: expiresAt?.toUtc(),
      createdAt: now,
      modifiedAt: now,
      version: 1,
      blobFileName: blobFileName,
      plaintextSizeBytes: bytes.length,
    );

    // Blob first, then the row. The two failure shapes are not equally
    // bad: a blob with no row is invisible and merely wastes space, while
    // a row with no blob is a document that appears in the list and then
    // fails to open. So the row — the thing that makes a document
    // visible — is written last.
    await _fileStorage.write(blobFileName, blob);
    try {
      await _dao.insert(document);
    } on Exception {
      // Roll the blob back so a failed insert leaves nothing behind.
      // A crash between the two writes can still orphan a blob; that is
      // recoverable by a sweep and is the lesser failure.
      await _fileStorage.delete(blobFileName);
      rethrow;
    }

    AppLogger.instance.info('Document added: $id');
    return document;
  }

  @override
  Future<Uint8List> openDocument(String id) async {
    final document = await _dao.findById(id);
    if (document == null) {
      throw DocumentNotFoundException('No document with id "$id".');
    }

    final blob = await _fileStorage.read(document.blobFileName);

    // Passing the id as the document identity is what makes a swapped
    // blob fail authentication rather than decrypt into the wrong record.
    return _encryption.decrypt(
      blob,
      keyId: encryptionKeyId,
      documentId: id,
    );
  }

  @override
  Future<List<Document>> listDocuments() => _dao.findAll();

  @override
  Future<Document?> getDocument(String id) => _dao.findById(id);

  @override
  Future<Document> updateDocument(Document document) async {
    // The caller supplies the edited metadata; bookkeeping is set here so
    // it cannot be forgotten or forged by a call site.
    final updated = document.copyWith(
      modifiedAt: _clock().toUtc(),
      version: document.version + 1,
    );

    final rows = await _dao.update(updated);
    if (rows == 0) {
      throw DocumentNotFoundException('No document with id "${document.id}".');
    }

    AppLogger.instance.info('Document updated: ${document.id}');
    return updated;
  }

  @override
  Future<void> deleteDocument(String id) async {
    final document = await _dao.findById(id);
    if (document == null) {
      throw DocumentNotFoundException('No document with id "$id".');
    }

    // Row first, then the blob — the mirror of addDocument's reasoning.
    // If the blob delete fails afterwards, the leftover file is invisible
    // and unreadable (its key is unchanged but nothing references it);
    // the reverse order would leave a listed document that cannot open.
    await _dao.deleteById(id);
    await _fileStorage.delete(document.blobFileName);

    AppLogger.instance.info('Document deleted: $id');
  }
}
