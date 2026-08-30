import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:safekeep/security/encryption/aes_gcm_encryption_service.dart';
import 'package:safekeep/security/encryption/encrypted_blob.dart';
import 'package:safekeep/security/encryption/encryption_key_source.dart';
import 'package:safekeep/security/security_exceptions.dart';

/// Minimal in-memory key source. The cipher only needs "give me a key",
/// so faking it takes three lines and needs no vault or platform channel.
class _FakeKeySource implements EncryptionKeySource {
  _FakeKeySource(this.keys);

  final Map<String, Uint8List> keys;

  @override
  Future<Uint8List> encryptionKeyFor(String keyId) async => keys[keyId]!;
}

Uint8List _key(int fill) => Uint8List(32)..fillRange(0, 32, fill);

/// Pseudo-random but reproducible bytes, so a failure is debuggable.
Uint8List _randomBytes(int length, {int seed = 42}) {
  final random = Random(seed);
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = random.nextInt(256);
  }
  return bytes;
}

void main() {
  const keyId = 'master';
  const docId = 'doc-1';
  late AesGcmEncryptionService service;

  setUp(() {
    service = AesGcmEncryptionService(
      keySource: _FakeKeySource({keyId: _key(0x01)}),
    );
  });

  group('round trip', () {
    test('small payload decrypts to the exact original bytes', () async {
      final plaintext = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);

      final blob = await service.encrypt(
        plaintext,
        keyId: keyId,
        documentId: docId,
      );
      final result = await service.decrypt(
        blob,
        keyId: keyId,
        documentId: docId,
      );

      expect(result, plaintext);
    });

    test('multi-MB payload decrypts to the exact original bytes', () async {
      // 5 MB stands in for a scanned multi-page PDF.
      final plaintext = _randomBytes(5 * 1024 * 1024);

      final blob = await service.encrypt(
        plaintext,
        keyId: keyId,
        documentId: docId,
      );
      final result = await service.decrypt(
        blob,
        keyId: keyId,
        documentId: docId,
      );

      expect(result.length, plaintext.length);
      expect(result, plaintext);
    });

    test('empty payload round-trips', () async {
      final blob = await service.encrypt(
        Uint8List(0),
        keyId: keyId,
        documentId: docId,
      );

      expect(
        await service.decrypt(blob, keyId: keyId, documentId: docId),
        isEmpty,
      );
    });

    test('single byte round-trips', () async {
      final plaintext = Uint8List.fromList([0xFF]);

      final blob = await service.encrypt(
        plaintext,
        keyId: keyId,
        documentId: docId,
      );

      expect(
        await service.decrypt(blob, keyId: keyId, documentId: docId),
        plaintext,
      );
    });

    test('all-zero payload round-trips', () async {
      final plaintext = Uint8List(1024);

      final blob = await service.encrypt(
        plaintext,
        keyId: keyId,
        documentId: docId,
      );

      expect(
        await service.decrypt(blob, keyId: keyId, documentId: docId),
        plaintext,
      );
    });

    test('blob is exactly 29 bytes longer than the plaintext', () async {
      final plaintext = _randomBytes(500);

      final blob = await service.encrypt(
        plaintext,
        keyId: keyId,
        documentId: docId,
      );

      expect(blob.length, plaintext.length + EncryptedBlob.headerLength);
    });
  });

  group('nonce is never reused', () {
    test(
      'encrypting identical plaintext twice yields different ciphertext',
      () async {
        final plaintext = Uint8List.fromList([9, 9, 9, 9, 9, 9, 9, 9]);

        final first = await service.encrypt(
          plaintext,
          keyId: keyId,
          documentId: docId,
        );
        final second = await service.encrypt(
          plaintext,
          keyId: keyId,
          documentId: docId,
        );

        // Identical output would mean a fixed nonce, which in GCM leaks
        // the XOR of plaintexts and enables tag forgery.
        expect(first, isNot(second));

        // Both must still decrypt correctly.
        expect(
          await service.decrypt(first, keyId: keyId, documentId: docId),
          plaintext,
        );
        expect(
          await service.decrypt(second, keyId: keyId, documentId: docId),
          plaintext,
        );
      },
    );

    test('the differing part is the nonce, not just the tag', () async {
      final plaintext = Uint8List.fromList([9, 9, 9, 9]);

      final first = EncryptedBlob.unpack(
        await service.encrypt(plaintext, keyId: keyId, documentId: docId),
      );
      final second = EncryptedBlob.unpack(
        await service.encrypt(plaintext, keyId: keyId, documentId: docId),
      );

      expect(first.nonce, isNot(second.nonce));
    });

    test('100 encryptions produce 100 distinct nonces', () async {
      final plaintext = Uint8List.fromList([1, 2, 3]);

      final nonces = <String>{};
      for (var i = 0; i < 100; i++) {
        final blob = await service.encrypt(
          plaintext,
          keyId: keyId,
          documentId: docId,
        );
        nonces.add(EncryptedBlob.unpack(blob).nonce.join(','));
      }

      expect(nonces.length, 100);
    });
  });

  group('decryption fails loudly', () {
    test('wrong key throws DecryptionAuthenticationException', () async {
      final plaintext = Uint8List.fromList([1, 2, 3, 4]);
      final blob = await service.encrypt(
        plaintext,
        keyId: keyId,
        documentId: docId,
      );

      final wrongKeyService = AesGcmEncryptionService(
        keySource: _FakeKeySource({keyId: _key(0x02)}),
      );

      // Must throw, never return garbage plaintext.
      await expectLater(
        () => wrongKeyService.decrypt(blob, keyId: keyId, documentId: docId),
        throwsA(isA<DecryptionAuthenticationException>()),
      );
    });

    test('flipping one ciphertext byte is detected by the tag', () async {
      final plaintext = _randomBytes(256);
      final blob = await service.encrypt(
        plaintext,
        keyId: keyId,
        documentId: docId,
      );

      // Flip a single bit in the middle of the ciphertext body.
      final tampered = Uint8List.fromList(blob);
      const index = EncryptedBlob.headerLength + 10;
      tampered[index] = tampered[index] ^ 0x01;

      await expectLater(
        () => service.decrypt(tampered, keyId: keyId, documentId: docId),
        throwsA(isA<DecryptionAuthenticationException>()),
      );
    });

    test('tampering with the nonce is detected', () async {
      final blob = await service.encrypt(
        _randomBytes(64),
        keyId: keyId,
        documentId: docId,
      );

      final tampered = Uint8List.fromList(blob);
      tampered[1] = tampered[1] ^ 0xFF;

      await expectLater(
        () => service.decrypt(tampered, keyId: keyId, documentId: docId),
        throwsA(isA<DecryptionAuthenticationException>()),
      );
    });

    test('tampering with the auth tag is detected', () async {
      final blob = await service.encrypt(
        _randomBytes(64),
        keyId: keyId,
        documentId: docId,
      );

      final tampered = Uint8List.fromList(blob);
      tampered[13] = tampered[13] ^ 0xFF;

      await expectLater(
        () => service.decrypt(tampered, keyId: keyId, documentId: docId),
        throwsA(isA<DecryptionAuthenticationException>()),
      );
    });

    test('truncated ciphertext is detected', () async {
      final blob = await service.encrypt(
        _randomBytes(256),
        keyId: keyId,
        documentId: docId,
      );

      final truncated = Uint8List.sublistView(blob, 0, blob.length - 10);

      await expectLater(
        () => service.decrypt(truncated, keyId: keyId, documentId: docId),
        throwsA(isA<DecryptionAuthenticationException>()),
      );
    });

    test('every single-byte corruption in a blob is caught', () async {
      // Exhaustive sweep over a small blob: no byte position may be
      // modifiable without detection.
      final plaintext = _randomBytes(16);
      final blob = await service.encrypt(
        plaintext,
        keyId: keyId,
        documentId: docId,
      );

      for (var i = 0; i < blob.length; i++) {
        final tampered = Uint8List.fromList(blob);
        tampered[i] = tampered[i] ^ 0xFF;

        await expectLater(
          () => service.decrypt(tampered, keyId: keyId, documentId: docId),
          throwsA(isA<SecurityException>()),
          reason: 'corruption at byte $i went undetected',
        );
      }
    });

    test('garbage input throws MalformedCiphertextException', () async {
      await expectLater(
        () =>
            service.decrypt(_randomBytes(10), keyId: keyId, documentId: docId),
        throwsA(isA<MalformedCiphertextException>()),
      );
    });
  });

  group('key validation', () {
    test('rejects a key that is not 32 bytes', () async {
      final shortKeyService = AesGcmEncryptionService(
        keySource: _FakeKeySource({keyId: Uint8List(16)}),
      );

      await expectLater(
        () => shortKeyService.encrypt(
          Uint8List(4),
          keyId: keyId,
          documentId: docId,
        ),
        throwsArgumentError,
      );
    });
  });

  group('document binding (blob substitution defence)', () {
    test('a blob cannot be decrypted under a different documentId', () async {
      // The substitution attack: all documents share one vault key, so
      // without AAD binding, any blob authenticated in any position.
      final plaintext = _randomBytes(128);
      final blob = await service.encrypt(
        plaintext,
        keyId: keyId,
        documentId: 'document-A',
      );

      await expectLater(
        () => service.decrypt(
          blob,
          keyId: keyId,
          documentId: 'document-B',
        ),
        throwsA(isA<DecryptionAuthenticationException>()),
      );
    });

    test('swapping two blobs between documents is detected', () async {
      final docA = _randomBytes(64, seed: 1);
      final docB = _randomBytes(64, seed: 2);

      final blobA = await service.encrypt(
        docA,
        keyId: keyId,
        documentId: 'A',
      );
      final blobB = await service.encrypt(
        docB,
        keyId: keyId,
        documentId: 'B',
      );

      // Attacker swaps the two stored blobs.
      await expectLater(
        () => service.decrypt(blobB, keyId: keyId, documentId: 'A'),
        throwsA(isA<DecryptionAuthenticationException>()),
      );
      await expectLater(
        () => service.decrypt(blobA, keyId: keyId, documentId: 'B'),
        throwsA(isA<DecryptionAuthenticationException>()),
      );
    });

    test('the correct documentId still round-trips', () async {
      final plaintext = _randomBytes(128);
      final blob = await service.encrypt(
        plaintext,
        keyId: keyId,
        documentId: 'document-A',
      );

      expect(
        await service.decrypt(
          blob,
          keyId: keyId,
          documentId: 'document-A',
        ),
        plaintext,
      );
    });

    test('a one-character difference in documentId is detected', () async {
      final blob = await service.encrypt(
        _randomBytes(32),
        keyId: keyId,
        documentId: 'document-1',
      );

      await expectLater(
        () => service.decrypt(
          blob,
          keyId: keyId,
          documentId: 'document-2',
        ),
        throwsA(isA<DecryptionAuthenticationException>()),
      );
    });

    test('a non-ASCII documentId round-trips', () async {
      const id = 'passeport-日本語-🔐';
      final plaintext = _randomBytes(32);

      final blob = await service.encrypt(
        plaintext,
        keyId: keyId,
        documentId: id,
      );

      expect(
        await service.decrypt(blob, keyId: keyId, documentId: id),
        plaintext,
      );
    });
  });

  group('key isolation', () {
    test(
      'data encrypted under one keyId cannot be read with another',
      () async {
        final multiKeyService = AesGcmEncryptionService(
          keySource: _FakeKeySource({'a': _key(0x0A), 'b': _key(0x0B)}),
        );
        final plaintext = Uint8List.fromList([1, 2, 3]);

        final blob = await multiKeyService.encrypt(
          plaintext,
          keyId: 'a',
          documentId: docId,
        );

        expect(
          await multiKeyService.decrypt(blob, keyId: 'a', documentId: docId),
          plaintext,
        );
        await expectLater(
          () => multiKeyService.decrypt(blob, keyId: 'b', documentId: docId),
          throwsA(isA<DecryptionAuthenticationException>()),
        );
      },
    );
  });
}
