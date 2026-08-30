import 'dart:convert';

import 'package:safekeep/data/database/app_database.dart';
import 'package:safekeep/domain/models/document.dart';
import 'package:safekeep/domain/models/document_category.dart';
import 'package:sqflite_sqlcipher/sqlite_api.dart';

/// Reads and writes [Document] metadata rows.
///
/// Deliberately the only place that knows the table's column names and
/// row encoding, so a schema change has exactly one call site to update.
///
/// # Encoding choices
///
/// * **Timestamps** are stored as milliseconds since the Unix epoch, in
///   UTC. SQLite has no date type, and storing a formatted string would
///   sort lexicographically and depend on the device's locale and
///   timezone — both of which can change between writes and reads.
/// * **Tags** are stored as a JSON array in a single column. A join table
///   would be the textbook answer, but tags are always read and written
///   with their document and are never queried independently yet. When
///   tag search arrives (a later phase), revisit this.
/// * **Category** is stored by its stable string, never its enum index.
class DocumentDao {
  const DocumentDao({required AppDatabase database}) : this._(database);

  const DocumentDao._(this._database);

  final AppDatabase _database;

  Database get _db => _database.database;

  Future<void> insert(Document document) async {
    await _db.insert(
      AppDatabase.documentsTable,
      _toRow(document),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<Document?> findById(String id) async {
    final rows = await _db.query(
      AppDatabase.documentsTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  /// All documents, newest first.
  Future<List<Document>> findAll() async {
    final rows = await _db.query(
      AppDatabase.documentsTable,
      orderBy: 'created_at DESC',
    );
    return rows.map(_fromRow).toList();
  }

  /// Replaces the row for [document]. Returns the number of rows changed,
  /// so callers can distinguish "updated" from "no such document".
  Future<int> update(Document document) {
    return _db.update(
      AppDatabase.documentsTable,
      _toRow(document),
      where: 'id = ?',
      whereArgs: [document.id],
    );
  }

  /// Deletes the row. Returns the number of rows removed.
  Future<int> deleteById(String id) {
    return _db.delete(
      AppDatabase.documentsTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> count() async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${AppDatabase.documentsTable}',
    );
    return (result.first['c'] as int?) ?? 0;
  }

  Map<String, Object?> _toRow(Document document) => {
    'id': document.id,
    'title': document.title,
    'category': document.category.storageValue,
    'tags': jsonEncode(document.tags),
    'notes': document.notes,
    'expires_at': document.expiresAt?.toUtc().millisecondsSinceEpoch,
    'created_at': document.createdAt.toUtc().millisecondsSinceEpoch,
    'modified_at': document.modifiedAt.toUtc().millisecondsSinceEpoch,
    'version': document.version,
    'blob_file_name': document.blobFileName,
    'plaintext_size_bytes': document.plaintextSizeBytes,
  };

  Document _fromRow(Map<String, Object?> row) {
    final expiresAt = row['expires_at'] as int?;
    return Document(
      id: row['id']! as String,
      title: row['title']! as String,
      category: DocumentCategory.fromStorage(row['category']! as String),
      tags: _decodeTags(row['tags'] as String?),
      notes: row['notes'] as String?,
      expiresAt: expiresAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(expiresAt, isUtc: true),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row['created_at']! as int,
        isUtc: true,
      ),
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(
        row['modified_at']! as int,
        isUtc: true,
      ),
      version: row['version']! as int,
      blobFileName: row['blob_file_name']! as String,
      plaintextSizeBytes: row['plaintext_size_bytes']! as int,
    );
  }

  /// Decodes the tag column, tolerating a malformed value.
  ///
  /// A corrupt tags column must not make a document unreadable — the
  /// document's bytes are unaffected, and losing its tags is far better
  /// than losing access to it. Everything else in the row is required and
  /// deliberately throws if absent.
  List<String> _decodeTags(String? encoded) {
    if (encoded == null || encoded.isEmpty) return const [];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return const [];
      return decoded.whereType<String>().toList();
    } on FormatException {
      return const [];
    }
  }
}
