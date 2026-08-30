import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:safekeep/data/database/app_database.dart';
import 'package:safekeep/data/database/database_opener.dart';
import 'package:safekeep/data/database/document_dao.dart';
import 'package:safekeep/domain/models/document.dart';
import 'package:safekeep/domain/models/document_category.dart';
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
