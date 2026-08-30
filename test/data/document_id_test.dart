import 'package:flutter_test/flutter_test.dart';
import 'package:safekeep/data/document_id.dart';

void main() {
  group('DocumentId', () {
    test('is 32 lowercase hex characters', () {
      expect(DocumentId.generate(), matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('is 128 bits of randomness', () {
      expect(DocumentId.lengthBytes, 16);
    });

    test('produces a distinct value every call', () {
      // A collision would overwrite another document's blob AND make the
      // survivor's ciphertext appear valid under the wrong record, since
      // the id is the AES-GCM associated data.
      final ids = List.generate(1000, (_) => DocumentId.generate()).toSet();

      expect(ids.length, 1000);
    });

    test('blobFileName appends the blob suffix', () {
      expect(DocumentId.blobFileName('abc123'), 'abc123.blob');
    });

    test('generated names pass the blob-storage name validation', () {
      // The storage layer rejects anything that could escape the vault
      // directory; generated ids must never trip that.
      final safeName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');

      for (var i = 0; i < 50; i++) {
        final name = DocumentId.blobFileName(DocumentId.generate());
        expect(safeName.hasMatch(name), isTrue, reason: name);
      }
    });
  });
}
