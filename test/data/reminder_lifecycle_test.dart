import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:safekeep/data/database/app_database.dart';
import 'package:safekeep/data/database/database_opener.dart';
import 'package:safekeep/data/database/document_dao.dart';
import 'package:safekeep/data/database/settings_dao.dart';
import 'package:safekeep/data/reminders/reminder_scheduler.dart';
import 'package:safekeep/data/storage/document_file_storage.dart';
import 'package:safekeep/data/vault_document_repository.dart';
import 'package:safekeep/domain/models/document_category.dart';
import 'package:safekeep/domain/models/reminder_settings.dart';
import 'package:safekeep/security/auth/biometric_gate.dart';
import 'package:safekeep/security/encryption/aes_gcm_encryption_service.dart';
import 'package:safekeep/security/key_management/kdf_parameters.dart';
import 'package:safekeep/security/key_management/secure_key_value_store.dart';
import 'package:safekeep/security/key_management/vault_key_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Reminders are scheduled by the repository rather than by whichever
/// screen saved the document, so that scheduling cannot be forgotten.
/// These tests pin that behaviour to the repository.

class _FakeStore implements SecureKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _AlwaysAllowGate implements BiometricGate {
  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<BiometricCapability> capability() async =>
      BiometricCapability.fingerprint;

  @override
  Future<bool> authenticate({required String reason}) async => true;
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
        singleInstance: false,
      ),
    );
  }
}

/// Records what the repository asks of the scheduler.
class _RecordingScheduler implements ReminderScheduler {
  final List<({String id, DateTime expiresAt, ReminderSettings settings})>
  scheduled = [];
  final List<String> cancelled = [];
  int cancelAllCalls = 0;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> scheduleFor({
    required String documentId,
    required DateTime expiresAt,
    required ReminderSettings settings,
  }) async {
    scheduled.add((id: documentId, expiresAt: expiresAt, settings: settings));
  }

  @override
  Future<void> cancelFor(String documentId) async => cancelled.add(documentId);

  @override
  Future<void> cancelAll() async => cancelAllCalls++;
}

const _fastParams = KdfParameters(
  memoryKib: 64,
  iterations: 1,
  parallelism: 1,
  keyLengthBytes: 32,
);

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory vaultDir;
  late AppDatabase database;
  late SettingsDao settingsDao;
  late _RecordingScheduler scheduler;
  late VaultDocumentRepository vault;

  setUp(() async {
    vaultDir = Directory.systemTemp.createTempSync('safekeep_reminder_test');
    final keyManager = VaultKeyManager(
      store: _FakeStore(),
      biometricGate: _AlwaysAllowGate(),
      setupParameters: _fastParams,
    );
    await keyManager.setUpVault(passphrase: 'correct horse battery staple');

    database = AppDatabase(opener: _InMemoryOpener());
    await database.open(await keyManager.databaseKey());
    settingsDao = SettingsDao(database: database);
    scheduler = _RecordingScheduler();

    vault = VaultDocumentRepository(
      encryption: AesGcmEncryptionService(keySource: keyManager),
      fileStorage: FileSystemDocumentFileStorage(directory: vaultDir),
      dao: DocumentDao(database: database),
      settingsDao: settingsDao,
      reminders: scheduler,
    );
  });

  tearDown(() async {
    await database.close();
    if (vaultDir.existsSync()) vaultDir.deleteSync(recursive: true);
  });

  Future<void> addDocument({DateTime? expiresAt, String title = 'Passport'}) {
    return vault
        .addDocument(
          bytes: Uint8List.fromList(List.filled(64, 1)),
          title: title,
          category: DocumentCategory.identity,
          mimeType: 'application/pdf',
          expiresAt: expiresAt,
        )
        .then((_) {});
  }

  group('adding', () {
    test('a document with an expiry schedules reminders', () async {
      final expiry = DateTime.utc(2030, 6, 15);

      await addDocument(expiresAt: expiry);

      expect(scheduler.scheduled.length, 1);
      expect(scheduler.scheduled.single.expiresAt, expiry);
      expect(scheduler.scheduled.single.settings, ReminderSettings.defaults);
    });

    test('a document without an expiry schedules nothing', () async {
      await addDocument();

      expect(scheduler.scheduled, isEmpty);
    });

    test('uses the saved offsets, not the defaults', () async {
      await settingsDao.writeReminderSettings(
        const ReminderSettings(offsetsInDays: {90, 1}),
      );

      await addDocument(expiresAt: DateTime.utc(2030));

      expect(
        scheduler.scheduled.single.settings,
        const ReminderSettings(offsetsInDays: {90, 1}),
      );
    });

    test('honours reminders being switched off entirely', () async {
      await settingsDao.writeReminderSettings(
        const ReminderSettings(offsetsInDays: {}),
      );

      await addDocument(expiresAt: DateTime.utc(2030));

      expect(scheduler.scheduled.single.settings.isEmpty, isTrue);
    });
  });

  group('editing', () {
    test('changing the expiry reschedules', () async {
      final document = await vault.addDocument(
        bytes: Uint8List.fromList(List.filled(64, 1)),
        title: 'Passport',
        category: DocumentCategory.identity,
        mimeType: 'application/pdf',
        expiresAt: DateTime.utc(2030),
      );
      scheduler.scheduled.clear();

      await vault.updateDocument(
        document.copyWith(expiresAt: DateTime.utc(2031)),
      );

      expect(scheduler.scheduled.single.expiresAt, DateTime.utc(2031));
    });

    test('clearing the expiry cancels rather than reschedules', () async {
      final document = await vault.addDocument(
        bytes: Uint8List.fromList(List.filled(64, 1)),
        title: 'Passport',
        category: DocumentCategory.identity,
        mimeType: 'application/pdf',
        expiresAt: DateTime.utc(2030),
      );
      scheduler.scheduled.clear();

      await vault.updateDocument(document.copyWith(clearExpiresAt: true));

      expect(scheduler.scheduled, isEmpty);
      expect(scheduler.cancelled, contains(document.id));
    });

    test('editing only the title still keeps reminders in step', () async {
      final document = await vault.addDocument(
        bytes: Uint8List.fromList(List.filled(64, 1)),
        title: 'Passport',
        category: DocumentCategory.identity,
        mimeType: 'application/pdf',
        expiresAt: DateTime.utc(2030),
      );
      scheduler.scheduled.clear();

      await vault.updateDocument(document.copyWith(title: 'Renewed'));

      expect(scheduler.scheduled.single.expiresAt, DateTime.utc(2030));
    });
  });

  group('deleting', () {
    test('cancels the document reminders', () async {
      final document = await vault.addDocument(
        bytes: Uint8List.fromList(List.filled(64, 1)),
        title: 'Passport',
        category: DocumentCategory.identity,
        mimeType: 'application/pdf',
        expiresAt: DateTime.utc(2030),
      );

      await vault.deleteDocument(document.id);

      // Otherwise a notification fires for a document that is gone.
      expect(scheduler.cancelled, contains(document.id));
    });
  });
}
