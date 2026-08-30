import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:safekeep/data/data_exceptions.dart';
import 'package:safekeep/data/storage/document_file_storage.dart';

Uint8List _bytes(int length, {int fill = 0xAB}) =>
    Uint8List(length)..fillRange(0, length, fill);

void main() {
  late Directory tempDir;
  late FileSystemDocumentFileStorage storage;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('safekeep_blob_test');
    storage = FileSystemDocumentFileStorage(directory: tempDir);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('round trip', () {
    test('written bytes read back identically', () async {
      final blob = _bytes(4096);

      await storage.write('doc.blob', blob);

      expect(await storage.read('doc.blob'), blob);
    });

    test('a multi-MB blob round-trips', () async {
      final blob = _bytes(5 * 1024 * 1024, fill: 0x5A);

      await storage.write('big.blob', blob);

      expect(await storage.read('big.blob'), blob);
    });

    test('an empty blob round-trips', () async {
      await storage.write('empty.blob', Uint8List(0));

      expect(await storage.read('empty.blob'), isEmpty);
    });

    test('creates the directory if it does not exist yet', () async {
      final nested = Directory('${tempDir.path}/does/not/exist');
      final nestedStorage = FileSystemDocumentFileStorage(directory: nested);

      await nestedStorage.write('doc.blob', _bytes(16));

      expect(await nestedStorage.read('doc.blob'), _bytes(16));
    });

    test('writing the same name twice replaces the blob', () async {
      await storage.write('doc.blob', _bytes(16, fill: 0x01));
      await storage.write('doc.blob', _bytes(32, fill: 0x02));

      final result = await storage.read('doc.blob');
      expect(result.length, 32);
      expect(result, everyElement(0x02));
    });
  });

  group('exists and delete', () {
    test('exists reflects whether a blob is present', () async {
      expect(await storage.exists('doc.blob'), isFalse);

      await storage.write('doc.blob', _bytes(8));
      expect(await storage.exists('doc.blob'), isTrue);

      await storage.delete('doc.blob');
      expect(await storage.exists('doc.blob'), isFalse);
    });

    test('deleting an absent blob succeeds', () async {
      // A partially failed earlier delete must always be cleanable.
      await expectLater(storage.delete('never-existed.blob'), completes);
    });

    test('the file is really gone from disk after delete', () async {
      await storage.write('doc.blob', _bytes(8));
      await storage.delete('doc.blob');

      expect(File('${tempDir.path}/doc.blob').existsSync(), isFalse);
    });
  });

  group('missing blobs fail loudly', () {
    test('reading an absent blob throws', () async {
      await expectLater(
        () => storage.read('missing.blob'),
        throwsA(isA<DocumentBlobMissingException>()),
      );
    });
  });

  group('file name validation', () {
    test('rejects path traversal', () async {
      // The name reaches a filesystem path; `..` would escape the vault.
      for (final name in ['../escape', '../../etc/passwd', 'a/../../b']) {
        await expectLater(
          () => storage.read(name),
          throwsA(isA<InvalidBlobNameException>()),
          reason: 'must reject "$name"',
        );
      }
    });

    test('rejects path separators', () async {
      for (final name in ['sub/doc.blob', r'sub\doc.blob', '/absolute']) {
        await expectLater(
          () => storage.write(name, _bytes(4)),
          throwsA(isA<InvalidBlobNameException>()),
          reason: 'must reject "$name"',
        );
      }
    });

    test('rejects empty and over-long names', () async {
      await expectLater(
        () => storage.read(''),
        throwsA(isA<InvalidBlobNameException>()),
      );
      await expectLater(
        () => storage.read('a' * 200),
        throwsA(isA<InvalidBlobNameException>()),
      );
    });

    test('accepts the hex-id names the repository generates', () async {
      const name = '0123456789abcdef0123456789abcdef.blob';

      await storage.write(name, _bytes(8));

      expect(await storage.exists(name), isTrue);
    });
  });

  group('atomic write', () {
    test('leaves no temporary file behind', () async {
      await storage.write('doc.blob', _bytes(1024));

      final leftovers = tempDir
          .listSync()
          .where((e) => e.path.endsWith('.tmp'))
          .toList();
      expect(leftovers, isEmpty);
    });
  });
}
