import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:safekeep/data/database/app_database.dart';
import 'package:safekeep/data/database/database_opener.dart';
import 'package:safekeep/data/database/document_dao.dart';
import 'package:safekeep/data/database/settings_dao.dart';
import 'package:safekeep/domain/models/document.dart';
import 'package:safekeep/domain/models/document_category.dart';
import 'package:safekeep/domain/models/reminder_settings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opens a real in-memory SQLite database.
///
/// Substitutes for SQLCipher, which needs a platform channel. The SQL,
/// schema, and encoding under test are identical either way; only
/// encryption-at-rest differs, and that is device-verified separately.
class _InMemoryOpener implements DatabaseOpener {
  @override
  Future<Database> open({
    required Uint8List key,
    required int version,
    required OnDatabaseCreateFn onCreate,
    required OnDatabaseVersionChangeFn onUpgrade,
  }) {
    return databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: version,
        onCreate: onCreate,
        onUpgrade: onUpgrade,
        // Without this, sqflite caches by path and every test asking for
        // ':memory:' shares one database — including one a previous test
        // already closed. Tests then pass or fail depending on order.
        singleInstance: false,
      ),
    );
  }
}

/// Opens a real file-backed database, so a migration survives a reopen.
class _FileOpener implements DatabaseOpener {
  _FileOpener(this.path);

  final String path;

  @override
  Future<Database> open({
    required Uint8List key,
    required int version,
    required OnDatabaseCreateFn onCreate,
    required OnDatabaseVersionChangeFn onUpgrade,
  }) {
    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: version,
        onCreate: onCreate,
        onUpgrade: onUpgrade,
        // Without this, sqflite caches by path and every test asking for
        // ':memory:' shares one database — including one a previous test
        // already closed. Tests then pass or fail depending on order.
        singleInstance: false,
      ),
    );
  }
}

Document _document({
  String id = 'doc-1',
  String title = 'Passport',
  DocumentCategory category = DocumentCategory.identity,
  List<String> tags = const ['travel'],
  String? notes,
  DateTime? expiresAt,
  int version = 1,
  DateTime? createdAt,
}) {
  final created = createdAt ?? DateTime.utc(2026, 5, 20, 10, 30);
  return Document(
    id: id,
    title: title,
    category: category,
    tags: tags,
    notes: notes,
    expiresAt: expiresAt,
    createdAt: created,
    modifiedAt: created,
    version: version,
    blobFileName: '$id.blob',
    plaintextSizeBytes: 2048,
    mimeType: 'application/pdf',
  );
}

void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase database;
  late DocumentDao dao;

  setUp(() async {
    database = AppDatabase(opener: _InMemoryOpener());
    await database.open(Uint8List(32));
    dao = DocumentDao(database: database);
  });

  tearDown(() => database.close());

  group('lifecycle', () {
    test('reports open state', () async {
      expect(database.isOpen, isTrue);

      await database.close();
      expect(database.isOpen, isFalse);
    });

    test('accessing the connection before opening throws', () {
      final unopened = AppDatabase(opener: _InMemoryOpener());

      // A programming error: callers must open after unlocking.
      expect(() => unopened.database, throwsStateError);
    });

    test('opening twice is a no-op rather than a second connection', () async {
      await database.open(Uint8List(32));

      expect(database.isOpen, isTrue);
      expect(await dao.count(), 0);
    });

    test('closing twice is safe', () async {
      await database.close();

      await expectLater(database.close(), completes);
    });
  });

  group('insert and read', () {
    test('a document round-trips through every field', () async {
      final document = _document(
        tags: const ['travel', 'urgent'],
        notes: 'Renew before the trip',
        expiresAt: DateTime.utc(2030, 1, 15),
      );

      await dao.insert(document);

      expect(await dao.findById('doc-1'), document);
    });

    test('nullable fields survive being null', () async {
      final document = _document();

      await dao.insert(document);

      final stored = await dao.findById('doc-1');
      expect(stored!.notes, isNull);
      expect(stored.expiresAt, isNull);
    });

    test('an empty tag list round-trips', () async {
      await dao.insert(_document(tags: const []));

      expect((await dao.findById('doc-1'))!.tags, isEmpty);
    });

    test('findById returns null for an unknown id', () async {
      expect(await dao.findById('nope'), isNull);
    });

    test(
      'a duplicate id is rejected rather than silently overwriting',
      () async {
        await dao.insert(_document());

        // Overwriting would orphan the first document's blob on disk.
        await expectLater(
          () => dao.insert(_document(title: 'Different')),
          throwsA(isA<DatabaseException>()),
        );
      },
    );

    test('timestamps survive as UTC to the millisecond', () async {
      final created = DateTime.utc(2026, 5, 20, 10, 30, 45, 123);
      await dao.insert(_document(createdAt: created));

      final stored = await dao.findById('doc-1');
      expect(stored!.createdAt, created);
      expect(stored.createdAt.isUtc, isTrue);
    });

    test('unicode in titles and tags survives', () async {
      await dao.insert(
        _document(title: 'Pasaporte — 日本 🛂', tags: const ['viaje', '重要']),
      );

      final stored = await dao.findById('doc-1');
      expect(stored!.title, 'Pasaporte — 日本 🛂');
      expect(stored.tags, ['viaje', '重要']);
    });

    test('a quote in a title does not break the query', () async {
      // Guards against string interpolation creeping into the SQL.
      await dao.insert(_document(title: "Rob's ID'; DROP TABLE documents;--"));

      final stored = await dao.findById('doc-1');
      expect(stored!.title, "Rob's ID'; DROP TABLE documents;--");
      expect(await dao.count(), 1, reason: 'table must still exist');
    });
  });

  group('findAll', () {
    test('returns every document, newest first', () async {
      await dao.insert(
        _document(id: 'old', createdAt: DateTime.utc(2020)),
      );
      await dao.insert(
        _document(id: 'new', createdAt: DateTime.utc(2026)),
      );

      final all = await dao.findAll();

      expect(all.map((d) => d.id), ['new', 'old']);
    });

    test('is empty for a fresh vault', () async {
      expect(await dao.findAll(), isEmpty);
    });
  });

  group('update', () {
    test('changes the stored row', () async {
      await dao.insert(_document());
      final updated = _document(title: 'Renewed passport', version: 2);

      expect(await dao.update(updated), 1);
      expect((await dao.findById('doc-1'))!.title, 'Renewed passport');
    });

    test('reports zero rows for an unknown document', () async {
      expect(await dao.update(_document(id: 'ghost')), 0);
    });

    test('does not touch the blob reference', () async {
      await dao.insert(_document());

      await dao.update(_document(title: 'Renamed'));

      expect((await dao.findById('doc-1'))!.blobFileName, 'doc-1.blob');
    });
  });

  group('delete', () {
    test('removes the row and reports the count', () async {
      await dao.insert(_document());

      expect(await dao.deleteById('doc-1'), 1);
      expect(await dao.findById('doc-1'), isNull);
      expect(await dao.count(), 0);
    });

    test('reports zero for an unknown document', () async {
      expect(await dao.deleteById('ghost'), 0);
    });

    test('leaves other documents untouched', () async {
      await dao.insert(_document(id: 'a'));
      await dao.insert(_document(id: 'b'));

      await dao.deleteById('a');

      expect(await dao.count(), 1);
      expect(await dao.findById('b'), isNotNull);
    });
  });

  group('schema migration', () {
    test(
      'a v1 database gains the mime_type column with a safe default',
      () async {
        // A file-backed database, because an in-memory one is discarded
        // on close and a migration can only be observed across a reopen.
        final dir = Directory.systemTemp.createTempSync('safekeep_migrate');
        final path = '${dir.path}/vault.db';

        // Create the schema exactly as version 1 had it, with a row in
        // it, simulating a vault made before Phase 4 added the viewer.
        final v1 = await databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, version) async {
              await db.execute('''
                CREATE TABLE ${AppDatabase.documentsTable} (
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
              await db.insert(AppDatabase.documentsTable, {
                'id': 'legacy-1',
                'title': 'Old passport',
                'category': 'identity',
                'tags': '[]',
                'created_at': 1,
                'modified_at': 1,
                'version': 1,
                'blob_file_name': 'legacy-1.blob',
                'plaintext_size_bytes': 10,
              });
            },
          ),
        );
        await v1.close();

        // Reopening through AppDatabase runs the real migration.
        final upgraded = AppDatabase(opener: _FileOpener(path));
        await upgraded.open(Uint8List(32));
        final dao = DocumentDao(database: upgraded);

        final restored = await dao.findById('legacy-1');
        expect(restored, isNotNull);
        expect(
          restored!.title,
          'Old passport',
          reason: 'existing metadata must survive the migration',
        );
        expect(restored.mimeType, 'application/octet-stream');
        expect(restored.isPdf, isFalse);
        expect(restored.isImage, isFalse);

        await upgraded.close();
        dir.deleteSync(recursive: true);
      },
    );

    test('the current schema version is 3', () {
      expect(AppDatabase.schemaVersion, 3);
    });

    test('a v1 database also gains the settings table', () async {
      // Two migration steps must both apply when a version is skipped.
      final dir = Directory.systemTemp.createTempSync('safekeep_migrate2');
      final path = '${dir.path}/vault.db';

      final v1 = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE ${AppDatabase.documentsTable} (
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
          },
        ),
      );
      await v1.close();

      final upgraded = AppDatabase(opener: _FileOpener(path));
      await upgraded.open(Uint8List(32));

      final settings = SettingsDao(database: upgraded);
      // Readable means the table exists; defaults mean nothing was set.
      expect(
        await settings.readReminderSettings(),
        ReminderSettings.defaults,
      );

      await upgraded.close();
      dir.deleteSync(recursive: true);
    });

    test('reminder settings round-trip through the settings table', () async {
      final settings = SettingsDao(database: database);
      const chosen = ReminderSettings(offsetsInDays: {90, 7});

      await settings.writeReminderSettings(chosen);

      expect(await settings.readReminderSettings(), chosen);
    });

    test('writing settings twice replaces rather than duplicates', () async {
      final settings = SettingsDao(database: database);

      await settings.writeReminderSettings(
        const ReminderSettings(offsetsInDays: {30}),
      );
      await settings.writeReminderSettings(
        const ReminderSettings(offsetsInDays: {7}),
      );

      expect(
        await settings.readReminderSettings(),
        const ReminderSettings(offsetsInDays: {7}),
      );
    });

    test('turning every reminder off is honoured, not reset', () async {
      final settings = SettingsDao(database: database);

      await settings.writeReminderSettings(
        const ReminderSettings(offsetsInDays: {}),
      );

      // An empty set must not silently fall back to the defaults.
      expect(
        (await settings.readReminderSettings()).isEmpty,
        isTrue,
      );
    });
  });

  group('resilience', () {
    test('a corrupt tags column loses tags, not the document', () async {
      await dao.insert(_document());
      await database.database.rawUpdate(
        'UPDATE ${AppDatabase.documentsTable} SET tags = ? WHERE id = ?',
        ['not valid json', 'doc-1'],
      );

      // Losing tags is far better than losing access to the document,
      // whose bytes are unaffected.
      final stored = await dao.findById('doc-1');
      expect(stored, isNotNull);
      expect(stored!.tags, isEmpty);
      expect(stored.title, 'Passport');
    });

    test('an unknown category decodes to other', () async {
      await dao.insert(_document());
      await database.database.rawUpdate(
        'UPDATE ${AppDatabase.documentsTable} SET category = ? WHERE id = ?',
        ['from-a-newer-build', 'doc-1'],
      );

      expect((await dao.findById('doc-1'))!.category, DocumentCategory.other);
    });
  });
}
