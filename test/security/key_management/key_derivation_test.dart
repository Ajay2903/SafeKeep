import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safekeep/security/key_management/kdf_parameters.dart';
import 'package:safekeep/security/key_management/key_derivation.dart';

/// Cheap parameters for tests that only care about behaviour, not cost.
///
/// Production uses [KdfParameters.current] (48 MiB, t=2), which would make
/// this suite take minutes. Determinism, domain separation, and salt
/// handling are all independent of the cost factors, so testing them at
/// low cost is sound — the *real* parameters are asserted separately in
/// the 'production parameters' group below.
const _fastParams = KdfParameters(
  memoryKib: 64,
  iterations: 1,
  parallelism: 1,
  keyLengthBytes: 32,
);

Uint8List _salt(int fill) => Uint8List(16)..fillRange(0, 16, fill);

void main() {
  const kdf = KeyDerivation();

  group('Argon2id conformance', () {
    // This is the test that justifies trusting package:cryptography's
    // pure-Dart Argon2id with the entire security of the app. If it ever
    // fails, STOP: the KDF is not producing standard Argon2id output and
    // every key derived by this build is suspect.
    test('matches the RFC 9106 section 5.3 Argon2id test vector', () async {
      final algorithm = Argon2id(
        parallelism: 4,
        memory: 32,
        iterations: 3,
        hashLength: 32,
      );

      final key = await algorithm.deriveKey(
        secretKey: SecretKey(List<int>.filled(32, 0x01)),
        nonce: List<int>.filled(16, 0x02),
        optionalSecret: List<int>.filled(8, 0x03),
        associatedData: List<int>.filled(12, 0x04),
      );

      expect(await key.extractBytes(), <int>[
        0x0d, 0x64, 0x0d, 0xf5, 0x8d, 0x78, 0x76, 0x6c, //
        0x08, 0xc0, 0x37, 0xa3, 0x4a, 0x8b, 0x53, 0xc9,
        0xd0, 0x1e, 0xf0, 0x45, 0x2d, 0x75, 0xb6, 0x5e,
        0xb5, 0x25, 0x20, 0xe9, 0x6b, 0x01, 0xe6, 0x59,
      ]);
    });
  });

  group('production parameters', () {
    // Guards against someone quietly weakening the KDF. Any change here
    // must be a deliberate edit to this test, with the migration
    // consequences understood (see KdfParameters' class doc).
    test('are the reviewed values', () {
      expect(KdfParameters.current.memoryKib, 49152, reason: '48 MiB');
      expect(KdfParameters.current.iterations, 2);
      expect(KdfParameters.current.parallelism, 1);
      expect(KdfParameters.current.keyLengthBytes, 32, reason: 'AES-256');
    });

    test('meet or exceed the OWASP minimum (19 MiB, t=2, p=1)', () {
      expect(KdfParameters.current.memoryKib, greaterThanOrEqualTo(19456));
      expect(KdfParameters.current.iterations, greaterThanOrEqualTo(2));
    });
  });

  group('determinism', () {
    test(
      'same passphrase + same salt produces the same key every time',
      () async {
        final salt = _salt(0xAB);

        final first = await kdf.deriveKeys(
          passphrase: 'correct horse battery staple',
          salt: salt,
          parameters: _fastParams,
        );
        final second = await kdf.deriveKeys(
          passphrase: 'correct horse battery staple',
          salt: salt,
          parameters: _fastParams,
        );

        // This is what makes restoring a vault on a new device possible.
        expect(first.encryptionKey, second.encryptionKey);
        expect(first.verifier, second.verifier);
      },
    );

    test(
      'a different passphrase with the same salt gives a different key',
      () async {
        final salt = _salt(0xAB);

        final first = await kdf.deriveKeys(
          passphrase: 'correct horse battery staple',
          salt: salt,
          parameters: _fastParams,
        );
        final second = await kdf.deriveKeys(
          passphrase: 'correct horse battery stapl3',
          salt: salt,
          parameters: _fastParams,
        );

        expect(first.encryptionKey, isNot(second.encryptionKey));
        expect(first.verifier, isNot(second.verifier));
      },
    );

    test(
      'the same passphrase with a different salt gives a different key',
      () async {
        final first = await kdf.deriveKeys(
          passphrase: 'correct horse battery staple',
          salt: _salt(0xAB),
          parameters: _fastParams,
        );
        final second = await kdf.deriveKeys(
          passphrase: 'correct horse battery staple',
          salt: _salt(0xCD),
          parameters: _fastParams,
        );

        // Two users sharing a passphrase must not share a key.
        expect(first.encryptionKey, isNot(second.encryptionKey));
      },
    );

    test('different cost parameters give a different key', () async {
      final salt = _salt(0xAB);

      final first = await kdf.deriveKeys(
        passphrase: 'passphrase',
        salt: salt,
        parameters: _fastParams,
      );
      final second = await kdf.deriveKeys(
        passphrase: 'passphrase',
        salt: salt,
        parameters: const KdfParameters(
          memoryKib: 64,
          iterations: 2,
          parallelism: 1,
          keyLengthBytes: 32,
        ),
      );

      // Precisely why parameters must be persisted per vault rather than
      // hardcoded: changing them changes the key.
      expect(first.encryptionKey, isNot(second.encryptionKey));
    });
  });

  group('domain separation', () {
    test('encryption key and verifier are different values', () async {
      final keys = await kdf.deriveKeys(
        passphrase: 'passphrase',
        salt: _salt(0x01),
        parameters: _fastParams,
      );

      // If these were equal, storing the verifier would store the key.
      expect(keys.encryptionKey, isNot(keys.verifier));
    });

    test('all three keys are mutually distinct', () async {
      final keys = await kdf.deriveKeys(
        passphrase: 'passphrase',
        salt: _salt(0x01),
        parameters: _fastParams,
      );

      // The database key is a sibling of the encryption key, not a
      // child: none may be derivable from another by inspection.
      expect(keys.encryptionKey, isNot(keys.databaseKey));
      expect(keys.encryptionKey, isNot(keys.verifier));
      expect(keys.databaseKey, isNot(keys.verifier));
    });

    test('the database key is deterministic', () async {
      final salt = _salt(0x03);
      final first = await kdf.deriveKeys(
        passphrase: 'passphrase',
        salt: salt,
        parameters: _fastParams,
      );
      final second = await kdf.deriveKeys(
        passphrase: 'passphrase',
        salt: salt,
        parameters: _fastParams,
      );

      expect(first.databaseKey, second.databaseKey);
    });

    test('both outputs are 32 bytes', () async {
      final keys = await kdf.deriveKeys(
        passphrase: 'passphrase',
        salt: _salt(0x01),
        parameters: _fastParams,
      );

      expect(keys.encryptionKey.length, 32);
      expect(keys.databaseKey.length, 32);
      expect(keys.verifier.length, 32);
    });

    test('a non-ASCII passphrase derives consistently', () async {
      // Guards the explicit UTF-8 encoding: a UTF-16 fallback would
      // derive different bytes for the same passphrase.
      final salt = _salt(0x02);
      const passphrase = 'pässwörd-日本語-🔐';

      final first = await kdf.deriveKeys(
        passphrase: passphrase,
        salt: salt,
        parameters: _fastParams,
      );
      final second = await kdf.deriveKeys(
        passphrase: passphrase,
        salt: salt,
        parameters: _fastParams,
      );

      expect(first.encryptionKey, second.encryptionKey);
    });
  });

  group('salt generation', () {
    test('produces 16 bytes', () {
      expect(KeyDerivation.generateSalt().length, 16);
      expect(KeyDerivation.saltLength, 16);
    });

    test('produces a different salt each call', () {
      final salts = List.generate(
        50,
        (_) => KeyDerivation.generateSalt().join(','),
      ).toSet();

      // A repeat here would mean the RNG is not secure/seeded properly.
      expect(salts.length, 50);
    });
  });

  group('DerivedKeys.destroy', () {
    test('zeroes both buffers', () async {
      final keys = await kdf.deriveKeys(
        passphrase: 'passphrase',
        salt: _salt(0x01),
        parameters: _fastParams,
      );

      keys.destroy();

      expect(keys.encryptionKey, everyElement(0));
      expect(keys.databaseKey, everyElement(0));
      expect(keys.verifier, everyElement(0));
    });
  });

  group('KdfParameters serialization', () {
    test('round-trips through JSON', () {
      final restored = KdfParameters.fromJson(KdfParameters.current.toJson());

      expect(restored, KdfParameters.current);
    });

    test('throws on malformed JSON rather than defaulting', () {
      // Silently falling back to defaults would derive the wrong key for
      // an existing vault and look like a wrong passphrase.
      expect(
        () => KdfParameters.fromJson('{"memoryKib": 1}'),
        throwsFormatException,
      );
      expect(() => KdfParameters.fromJson('[]'), throwsFormatException);
      expect(() => KdfParameters.fromJson('not json'), throwsFormatException);
    });
  });
}
