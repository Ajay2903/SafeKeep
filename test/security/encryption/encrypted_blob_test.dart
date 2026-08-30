import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:safekeep/security/encryption/encrypted_blob.dart';
import 'package:safekeep/security/security_exceptions.dart';

Uint8List _bytes(int length, int fill) =>
    Uint8List(length)..fillRange(0, length, fill);

void main() {
  group('EncryptedBlob layout', () {
    test('header is 29 bytes: 1 version + 12 nonce + 16 tag', () {
      expect(EncryptedBlob.versionLength, 1);
      expect(EncryptedBlob.nonceLength, 12);
      expect(EncryptedBlob.tagLength, 16);
      expect(EncryptedBlob.headerLength, 29);
    });

    test('packed blob is exactly 29 + plaintext length', () {
      final blob = EncryptedBlob.pack(
        nonce: _bytes(12, 0xAA),
        tag: _bytes(16, 0xBB),
        ciphertext: _bytes(100, 0xCC),
      );

      expect(blob.length, 29 + 100);
    });

    test('fields land at their documented offsets', () {
      final blob = EncryptedBlob.pack(
        nonce: _bytes(12, 0xAA),
        tag: _bytes(16, 0xBB),
        ciphertext: _bytes(4, 0xCC),
      );

      expect(blob[0], EncryptedBlob.version, reason: 'version byte first');
      expect(blob.sublist(1, 13), everyElement(0xAA), reason: 'nonce');
      expect(blob.sublist(13, 29), everyElement(0xBB), reason: 'tag');
      expect(blob.sublist(29), everyElement(0xCC), reason: 'ciphertext');
    });

    test('pack then unpack round-trips every field', () {
      final nonce = _bytes(12, 0x11);
      final tag = _bytes(16, 0x22);
      final ciphertext = _bytes(64, 0x33);

      final parsed = EncryptedBlob.unpack(
        EncryptedBlob.pack(nonce: nonce, tag: tag, ciphertext: ciphertext),
      );

      expect(parsed.nonce, nonce);
      expect(parsed.tag, tag);
      expect(parsed.ciphertext, ciphertext);
    });

    test('handles empty ciphertext without losing header framing', () {
      final parsed = EncryptedBlob.unpack(
        EncryptedBlob.pack(
          nonce: _bytes(12, 0x11),
          tag: _bytes(16, 0x22),
          ciphertext: Uint8List(0),
        ),
      );

      expect(parsed.ciphertext, isEmpty);
      expect(parsed.nonce.length, 12);
      expect(parsed.tag.length, 16);
    });
  });

  group('EncryptedBlob.pack rejects wrong-sized inputs', () {
    test('throws on a nonce that is not 12 bytes', () {
      expect(
        () => EncryptedBlob.pack(
          nonce: _bytes(11, 0),
          tag: _bytes(16, 0),
          ciphertext: _bytes(4, 0),
        ),
        throwsArgumentError,
      );
    });

    test('throws on a tag that is not 16 bytes', () {
      expect(
        () => EncryptedBlob.pack(
          nonce: _bytes(12, 0),
          tag: _bytes(15, 0),
          ciphertext: _bytes(4, 0),
        ),
        throwsArgumentError,
      );
    });
  });

  group('EncryptedBlob.unpack rejects malformed input', () {
    test('throws when the blob is shorter than the header', () {
      expect(
        () => EncryptedBlob.unpack(_bytes(28, 0)),
        throwsA(isA<MalformedCiphertextException>()),
      );
    });

    test('throws on an empty blob', () {
      expect(
        () => EncryptedBlob.unpack(Uint8List(0)),
        throwsA(isA<MalformedCiphertextException>()),
      );
    });

    test('rejects the pre-release v1 format', () {
      // v1 bound no associated data and was vulnerable to blob
      // substitution; accepting it would reintroduce that weakness.
      final blob = EncryptedBlob.pack(
        nonce: _bytes(12, 0),
        tag: _bytes(16, 0),
        ciphertext: _bytes(4, 0),
      )..[0] = 0x01;

      expect(
        () => EncryptedBlob.unpack(blob),
        throwsA(isA<MalformedCiphertextException>()),
      );
    });

    test('throws on an unknown format version', () {
      final blob = EncryptedBlob.pack(
        nonce: _bytes(12, 0),
        tag: _bytes(16, 0),
        ciphertext: _bytes(4, 0),
      )..[0] = 0x99;

      expect(
        () => EncryptedBlob.unpack(blob),
        throwsA(
          isA<MalformedCiphertextException>().having(
            (e) => e.message,
            'message',
            contains('version'),
          ),
        ),
      );
    });

    test('a header-only blob is well-formed with empty ciphertext', () {
      // Exactly 29 bytes is the boundary case: valid, just no payload.
      final blob = _bytes(29, 0)..[0] = EncryptedBlob.version;

      expect(EncryptedBlob.unpack(blob).ciphertext, isEmpty);
    });
  });

  group('EncryptedBlob.associatedData', () {
    test('is version || uint32be(len) || utf8(documentId)', () {
      final aad = EncryptedBlob.associatedData(documentId: 'abc');

      expect(aad.length, 1 + 4 + 3);
      expect(aad[0], EncryptedBlob.version, reason: 'version is bound');
      expect(aad.sublist(1, 5), [0, 0, 0, 3], reason: 'big-endian length');
      expect(aad.sublist(5), utf8.encode('abc'));
    });

    test('differs for different document ids', () {
      expect(
        EncryptedBlob.associatedData(documentId: 'a'),
        isNot(EncryptedBlob.associatedData(documentId: 'b')),
      );
    });

    test('is deterministic for the same id', () {
      expect(
        EncryptedBlob.associatedData(documentId: 'doc-1'),
        EncryptedBlob.associatedData(documentId: 'doc-1'),
      );
    });

    test('encodes the document id as UTF-8, not UTF-16', () {
      const id = 'é🔐';
      final aad = EncryptedBlob.associatedData(documentId: id);

      expect(aad.sublist(5), utf8.encode(id));
    });

    test('the length prefix keeps concatenations unambiguous', () {
      // Without a length prefix, ("ab","c") and ("a","bc") could collide
      // once a second field is ever appended after the id.
      expect(
        EncryptedBlob.associatedData(documentId: 'ab'),
        isNot(EncryptedBlob.associatedData(documentId: 'a')),
      );
      expect(
        EncryptedBlob.associatedData(documentId: 'ab').sublist(1, 5),
        [0, 0, 0, 2],
      );
    });

    test('handles an empty document id', () {
      final aad = EncryptedBlob.associatedData(documentId: '');

      expect(aad.length, 5);
      expect(aad.sublist(1, 5), [0, 0, 0, 0]);
    });
  });
}
