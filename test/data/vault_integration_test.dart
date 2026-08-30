import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:safekeep/data/data_exceptions.dart';
import 'package:safekeep/data/database/app_database.dart';
import 'package:safekeep/data/database/database_opener.dart';
import 'package:safekeep/data/database/document_dao.dart';
import 'package:safekeep/data/storage/document_file_storage.dart';
import 'package:safekeep/data/vault_document_repository.dart';
import 'package:safekeep/domain/models/document_category.dart';
import 'package:safekeep/security/auth/biometric_gate.dart';
import 'package:safekeep/security/encryption/aes_gcm_encryption_service.dart';
import 'package:safekeep/security/key_management/kdf_parameters.dart';
import 'package:safekeep/security/key_management/secure_key_value_store.dart';
import 'package:safekeep/security/key_management/vault_key_manager.dart';
import 'package:safekeep/security/security_exceptions.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// End-to-end Phase 2 acceptance: the whole vault wired together with
/// real cryptography, a real filesystem, and real SQL.
///
/// Only two things are substituted, both because they need platform
/// channels that cannot run under `flutter test`: Keystore/Keychain
/// becomes an in-memory map, and SQLCipher becomes plain in-memory
/// SQLite. Everything else — Argon2id, HKDF, AES-256-GCM, file I/O,
/// the schema and queries — is the production code path.

class _FakeStore implements SecureKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _FakeBiometricGate implements BiometricGate {
  bool succeeds = true;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> authenticate({required String reason}) async => succeeds;
}

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

/// Cheap KDF cost factors; the production values are pinned separately.
const _fastParams = KdfParameters(
  memoryKib: 64,
  iterations: 1,
  parallelism: 1,
  keyLengthBytes: 32,
);

const _passphrase = 'correct horse battery staple';

Uint8List _pdfBytes(int length, {int seed = 11}) {
  final random = Random(seed);
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = random.nextInt(256);
  }
  return bytes;
}

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory vaultDir;
  late _FakeStore secureStore;
  late _FakeBiometricGate gate;
  late VaultKeyManager keyManager;
  late AppDatabase database;
  late DocumentDao dao;
  late FileSystemDocumentFileStorage fileStorage;
  late VaultDocumentRepository vault;

  setUp(() async {
    vaultDir = Directory.systemTemp.createTempSync('safekeep_vault_test');
    secureStore = _FakeStore();
    gate = _FakeBiometricGate();

    keyManager = VaultKeyManager(
      store: secureStore,
      biometricGate: gate,
      setupParameters: _fastParams,
    );
    await keyManager.setUpVault(passphrase: _passphrase);

    database = AppDatabase(opener: _InMemoryOpener());
    await database.open(await keyManager.databaseKey());
    dao = DocumentDao(database: database);
    fileStorage = FileSystemDocumentFileStorage(directory: vaultDir);

    vault = VaultDocumentRepository(
      encryption: AesGcmEncryptionService(keySource: keyManager),
      fileStorage: fileStorage,
      dao: dao,
    );
  });

  tearDown(() async {
    await database.close();
    if (vaultDir.existsSync()) vaultDir.deleteSync(recursive: true);
  });

  group('add a document', () {
    test('the blob on disk is unreadable and a metadata row exists', () async {
      const secretText = 'PASSPORT NO. X1234567 — Ajay Tibrewal';
      final plaintext = Uint8List.fromList(utf8.encode(secretText));

      final document = await vault.addDocument(
        bytes: plaintext,
        title: 'Passport',
        category: DocumentCategory.identity,
        mimeType: 'application/pdf',
        tags: const ['travel'],
      );

      // 1. A metadata row exists and describes the document.
      final stored = await dao.findById(document.id);
      expect(stored, isNotNull);
      expect(stored!.title, 'Passport');
      expect(stored.category, DocumentCategory.identity);
      expect(stored.plaintextSizeBytes, plaintext.length);
      expect(stored.version, 1);

      // 2. A blob exists on disk under the recorded name.
      final blobFile = File('${vaultDir.path}/${document.blobFileName}');
      expect(blobFile.existsSync(), isTrue);

      // 3. That blob is unreadable: it contains none of the plaintext,
      //    in any obvious encoding, and is 29 bytes longer than the
      //    input (version + nonce + tag).
      final onDisk = blobFile.readAsBytesSync();
      expect(onDisk.length, plaintext.length + 29);
      expect(onDisk, isNot(plaintext));
      final asText = utf8.decode(onDisk, allowMalformed: true);
      expect(asText, isNot(contains(secretText)));
      expect(asText, isNot(contains('X1234567')));
      expect(asText, isNot(contains('PASSPORT')));
    });

    test('document bytes never enter the database', () async {
      const secretText = 'SECRET-DOCUMENT-CONTENT-9876';
      await vault.addDocument(
        bytes: Uint8List.fromList(utf8.encode(secretText)),
        title: 'Contract',
        category: DocumentCategory.contract,
        mimeType: 'application/pdf',
      );

      // Dump every value from every row and assert the content is absent.
      final rows = await database.database.query(AppDatabase.documentsTable);
      final dumped = rows.map((r) => r.values.join('|')).join('||');
      expect(dumped, isNot(contains(secretText)));
      expect(dumped, isNot(contains('9876')));
    });

    test('two documents get distinct ids and separate blobs', () async {
      final a = await vault.addDocument(
        bytes: _pdfBytes(512, seed: 1),
        title: 'A',
        category: DocumentCategory.tax,
        mimeType: 'application/pdf',
      );
      final b = await vault.addDocument(
        bytes: _pdfBytes(512, seed: 2),
        title: 'B',
        category: DocumentCategory.tax,
        mimeType: 'application/pdf',
      );

      expect(a.id, isNot(b.id));
      expect(await fileStorage.exists(a.blobFileName), isTrue);
      expect(await fileStorage.exists(b.blobFileName), isTrue);
    });
  });

  group('open a document', () {
    test('decrypts back to exactly the original bytes', () async {
      final original = _pdfBytes(256 * 1024);

      final document = await vault.addDocument(
        bytes: original,
        title: 'Scanned contract',
        category: DocumentCategory.contract,
        mimeType: 'application/pdf',
      );

      expect(await vault.openDocument(document.id), original);
    });

    test('a multi-MB document round-trips', () async {
      final original = _pdfBytes(3 * 1024 * 1024);

      final document = await vault.addDocument(
        bytes: original,
        title: 'Big scan',
        category: DocumentCategory.medical,
        mimeType: 'application/pdf',
      );

      expect(await vault.openDocument(document.id), original);
    });

    test('opening an unknown document fails loudly', () async {
      await expectLater(
        () => vault.openDocument('does-not-exist'),
        throwsA(isA<DocumentNotFoundException>()),
      );
    });

    test('a missing blob is reported as missing, not as corruption', () async {
      final document = await vault.addDocument(
        bytes: _pdfBytes(128),
        title: 'Doomed',
        category: DocumentCategory.other,
        mimeType: 'application/pdf',
      );
      await fileStorage.delete(document.blobFileName);

      await expectLater(
        () => vault.openDocument(document.id),
        throwsA(isA<DocumentBlobMissingException>()),
      );
    });

    test('a tampered blob fails authentication', () async {
      final document = await vault.addDocument(
        bytes: _pdfBytes(1024),
        title: 'Target',
        category: DocumentCategory.insurance,
        mimeType: 'application/pdf',
      );

      final file = File('${vaultDir.path}/${document.blobFileName}');
      final bytes = file.readAsBytesSync();
      bytes[100] = bytes[100] ^ 0x01;
      file.writeAsBytesSync(bytes);

      await expectLater(
        () => vault.openDocument(document.id),
        throwsA(isA<DecryptionAuthenticationException>()),
      );
    });

    test('swapping two documents blobs is detected', () async {
      final a = await vault.addDocument(
        bytes: _pdfBytes(256, seed: 1),
        title: 'A',
        category: DocumentCategory.tax,
        mimeType: 'application/pdf',
      );
      final b = await vault.addDocument(
        bytes: _pdfBytes(256, seed: 2),
        title: 'B',
        category: DocumentCategory.tax,
        mimeType: 'application/pdf',
      );

      // An attacker with write access swaps the two blob files.
      final fileA = File('${vaultDir.path}/${a.blobFileName}');
      final fileB = File('${vaultDir.path}/${b.blobFileName}');
      final bytesA = fileA.readAsBytesSync();
      fileA.writeAsBytesSync(fileB.readAsBytesSync());
      fileB.writeAsBytesSync(bytesA);

      // Both must fail: the document id is bound as associated data.
      await expectLater(
        () => vault.openDocument(a.id),
        throwsA(isA<DecryptionAuthenticationException>()),
      );
      await expectLater(
        () => vault.openDocument(b.id),
        throwsA(isA<DecryptionAuthenticationException>()),
      );
    });
  });

  group('list, update, delete', () {
    test('listing returns metadata without decrypting anything', () async {
      await vault.addDocument(
        bytes: _pdfBytes(64),
        title: 'One',
        category: DocumentCategory.identity,
        mimeType: 'application/pdf',
      );
      await vault.addDocument(
        bytes: _pdfBytes(64),
        title: 'Two',
        category: DocumentCategory.tax,
        mimeType: 'application/pdf',
      );

      final all = await vault.listDocuments();

      expect(all.length, 2);
      expect(all.map((d) => d.title), containsAll(['One', 'Two']));
    });

    test(
      'updating bumps version and modifiedAt, leaving the blob alone',
      () async {
        final document = await vault.addDocument(
          bytes: _pdfBytes(128),
          title: 'Original title',
          category: DocumentCategory.other,
          mimeType: 'application/pdf',
        );
        final original = await vault.openDocument(document.id);

        final updated = await vault.updateDocument(
          document.copyWith(title: 'Corrected title'),
        );

        expect(updated.title, 'Corrected title');
        expect(updated.version, 2);
        expect(updated.blobFileName, document.blobFileName);
        // The document itself is untouched by a metadata edit.
        expect(await vault.openDocument(document.id), original);
      },
    );

    test('updating an unknown document fails', () async {
      final document = await vault.addDocument(
        bytes: _pdfBytes(32),
        title: 'Real',
        category: DocumentCategory.other,
        mimeType: 'application/pdf',
      );
      await vault.deleteDocument(document.id);

      await expectLater(
        () => vault.updateDocument(document),
        throwsA(isA<DocumentNotFoundException>()),
      );
    });

    test('deleting removes both the row and the blob', () async {
      final document = await vault.addDocument(
        bytes: _pdfBytes(128),
        title: 'Temporary',
        category: DocumentCategory.other,
        mimeType: 'application/pdf',
      );

      await vault.deleteDocument(document.id);

      expect(await dao.findById(document.id), isNull);
      expect(await fileStorage.exists(document.blobFileName), isFalse);
      expect(await vault.listDocuments(), isEmpty);
    });
  });

  group('the vault is sealed when locked', () {
    test('adding is impossible while locked', () async {
      keyManager.lock();

      await expectLater(
        () => vault.addDocument(
          bytes: _pdfBytes(64),
          title: 'Nope',
          category: DocumentCategory.other,
          mimeType: 'application/pdf',
        ),
        throwsA(isA<VaultLockedException>()),
      );
    });

    test('an existing document cannot be opened while locked', () async {
      final document = await vault.addDocument(
        bytes: _pdfBytes(128),
        title: 'Locked away',
        category: DocumentCategory.identity,
        mimeType: 'application/pdf',
      );

      keyManager.lock();

      await expectLater(
        () => vault.openDocument(document.id),
        throwsA(isA<VaultLockedException>()),
      );
    });

    test('unlocking again restores access to the same bytes', () async {
      final original = _pdfBytes(4096);
      final document = await vault.addDocument(
        bytes: original,
        title: 'Persistent',
        category: DocumentCategory.identity,
        mimeType: 'application/pdf',
      );

      keyManager.lock();
      expect(await keyManager.unlockWithPassphrase(_passphrase), isTrue);

      expect(await vault.openDocument(document.id), original);
    });

    test('biometric unlock also restores access', () async {
      final original = _pdfBytes(2048);
      final document = await vault.addDocument(
        bytes: original,
        title: 'Persistent',
        category: DocumentCategory.identity,
        mimeType: 'application/pdf',
      );

      keyManager.lock();
      gate.succeeds = true;
      expect(await keyManager.unlockWithBiometrics(), isTrue);

      expect(await vault.openDocument(document.id), original);
    });
  });

  group('crypto-erase', () {
    test('deleting the vault makes remaining blobs undecryptable', () async {
      final document = await vault.addDocument(
        bytes: _pdfBytes(512),
        title: 'Doomed',
        category: DocumentCategory.other,
        mimeType: 'application/pdf',
      );
      final blobFile = File('${vaultDir.path}/${document.blobFileName}');
      expect(blobFile.existsSync(), isTrue);

      await keyManager.deleteVault();

      // The blob is still on disk, but the key is gone and cannot be
      // re-derived: the salt was destroyed with it.
      expect(blobFile.existsSync(), isTrue);
      await expectLater(
        () => vault.openDocument(document.id),
        throwsA(isA<VaultLockedException>()),
      );
      await expectLater(
        () => keyManager.unlockWithPassphrase(_passphrase),
        throwsA(isA<VaultNotInitializedException>()),
      );
    });
  });
}
