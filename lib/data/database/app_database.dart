import 'dart:typed_data';

import 'package:safekeep/data/database/database_opener.dart';
import 'package:sqflite_sqlcipher/sqlite_api.dart';

/// Owns the encrypted metadata database: its connection, schema, and
/// migrations.
///
/// # What lives here and what does not
///
/// Metadata only — titles, categories, tags, notes, expiry dates,
/// timestamps, and a *reference* to each document's blob. Document bytes
/// never enter the database. Keeping them out means listing a vault of
/// hundreds of documents touches no ciphertext, and a database dump can
/// never contain a document.
///
/// The database is encrypted at rest by SQLCipher under a key derived
/// from the vault's master key (see `KeyDerivation`). Metadata is
/// sensitive in its own right — "Divorce settlement" as a title says
/// plenty without the file — so it gets the same protection as the blobs.
class AppDatabase {
  AppDatabase({required DatabaseOpener opener}) : this._(opener);

  AppDatabase._(this._opener);

  /// Current schema version. Bump and add an [_upgrade] branch when the
  /// schema changes.
  static const int schemaVersion = 1;

  static const String documentsTable = 'documents';

  final DatabaseOpener _opener;

  Database? _database;

  /// Whether the database is currently open.
  bool get isOpen => _database != null;

  /// The open connection.
  ///
  /// Throws [StateError] if the database has not been opened — a
  /// programming error, since callers must open it after unlocking.
  Database get database {
    final database = _database;
    if (database == null) {
      throw StateError(
        'The metadata database is not open. Call open() after unlocking.',
      );
    }
    return database;
  }

  /// Opens the database with [key], creating the schema on first use.
  ///
  /// Calling this when already open is a no-op, so an unlock flow that
  /// runs twice cannot open two connections.
  Future<void> open(Uint8List key) async {
    if (_database != null) return;
    _database = await _opener.open(
      key: key,
      version: schemaVersion,
      onCreate: _create,
      onUpgrade: _upgrade,
    );
  }

  /// Closes the connection and forgets it.
  ///
  /// Called on lock: leaving an open handle would keep decrypted pages in
  /// SQLCipher's cache after the vault is supposed to be sealed.
  Future<void> close() async {
    final database = _database;
    _database = null;
    await database?.close();
  }

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $documentsTable (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        category TEXT NOT NULL,
        tags TEXT NOT NULL,
        notes TEXT,
        expires_at INTEGER,
        created_at INTEGER NOT NULL,
        modified_at INTEGER NOT NULL,
        version INTEGER NOT NULL,
        blob_file_name TEXT NOT NULL,
        plaintext_size_bytes INTEGER NOT NULL
      )
    ''');

    // Categories drive the main list grouping, and expiry drives the
    // reminder scan — both are read far more often than written.
    await db.execute(
      'CREATE INDEX idx_documents_category '
      'ON $documentsTable (category)',
    );
    await db.execute(
      'CREATE INDEX idx_documents_expires_at '
      'ON $documentsTable (expires_at)',
    );
  }

  static Future<void> _upgrade(Database db, int from, int to) async {
    // No migrations yet — schema version 1 is the first release.
    //
    // When one is needed, add an explicit `if (from < n)` block per step
    // so upgrades compose across skipped versions. Never drop or recreate
    // the documents table: the blobs on disk are keyed by rows in it, and
    // losing a row orphans a document that is then undecryptable, since
    // its id is the AES-GCM associated data.
    throw UnimplementedError(
      'No schema migration is defined from version $from to $to.',
    );
  }
}
