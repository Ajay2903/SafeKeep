import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safekeep/app/app.dart';
import 'package:safekeep/core/config/app_config.dart';
import 'package:safekeep/core/config/flavor.dart';
import 'package:safekeep/data/database/app_database.dart';
import 'package:safekeep/data/database/database_opener.dart';
import 'package:safekeep/domain/models/document.dart';
import 'package:safekeep/domain/models/document_category.dart';
import 'package:safekeep/domain/repositories/document_repository.dart';
import 'package:safekeep/presentation/vault/document_detail_screen.dart';
import 'package:safekeep/presentation/vault/vault_home_screen.dart';
import 'package:safekeep/security/auth/biometric_gate.dart';
import 'package:safekeep/security/key_management/key_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opening a document pushes a route, and a pushed route is a *sibling*
/// of the home route rather than a descendant of it. A provider placed in
/// `MaterialApp.home:` therefore sits below the Navigator and is
/// invisible to everything pushed onto it.
///
/// That is not a hypothetical: the document viewer reads the session
/// cubit to close itself when the vault locks, and threw
/// ProviderNotFoundException on every open until the provider was hoisted
/// above MaterialApp. This test walks the real path — list, tap, viewer —
/// so the regression cannot come back quietly.

class _UnlockedKeyManager implements KeyManager {
  bool unlocked = false;

  @override
  Future<bool> isInitialized() async => true;

  @override
  bool get isUnlocked => unlocked;

  @override
  Future<bool> unlockWithBiometrics() async {
    unlocked = true;
    return true;
  }

  @override
  Future<void> setUpVault({required String passphrase}) async {}

  @override
  Future<bool> verifyPassphrase(String passphrase) async => true;

  @override
  Future<bool> unlockWithPassphrase(String passphrase) async {
    unlocked = true;
    return true;
  }

  @override
  void lock() => unlocked = false;

  @override
  Future<Uint8List> encryptionKeyFor(String keyId) async => Uint8List(32);

  @override
  Future<Uint8List> databaseKey() async => Uint8List(32);

  @override
  Future<void> deleteVault() async {}
}

class _AvailableGate implements BiometricGate {
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
        // Without this, sqflite caches by path and every test asking for
        // ':memory:' shares one database — including one a previous test
        // already closed. Tests then pass or fail depending on order.
        singleInstance: false,
      ),
    );
  }
}

/// Serves one image document whose bytes decrypt to a 1x1 PNG.
class _OneDocumentRepository implements DocumentRepository {
  static final Document document = Document(
    id: 'doc-1',
    title: 'My passport',
    category: DocumentCategory.identity,
    tags: const ['travel'],
    createdAt: DateTime.utc(2026),
    modifiedAt: DateTime.utc(2026),
    version: 1,
    blobFileName: 'doc-1.blob',
    plaintextSizeBytes: 68,
    mimeType: 'image/png',
  );

  /// Smallest valid PNG, so the viewer has something real to decode.
  static final Uint8List pngBytes = Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ]);

  @override
  Future<List<Document>> listDocuments() async => [document];

  @override
  Future<Document?> getDocument(String id) async => document;

  @override
  Future<Uint8List> openDocument(String id) async => pngBytes;

  @override
  Future<void> deleteAllDocuments() async {}

  @override
  Future<void> deleteDocument(String id) async {}

  @override
  Future<Document> updateDocument(Document document) async => document;

  @override
  Future<Document> addDocument({
    required Uint8List bytes,
    required String title,
    required DocumentCategory category,
    required String mimeType,
    List<String> tags = const [],
    String? notes,
    DateTime? expiresAt,
  }) async => throw UnimplementedError();
}

/// Unlocks the vault and waits for the metadata database to open.
///
/// `runAsync` is required, not incidental. `testWidgets` runs inside a
/// fake-async zone, but sqflite's FFI database performs real async work
/// in a background isolate — work that fake time never advances, so
/// `pumpAndSettle` alone returns with the vault still locked.
Future<void> unlock(WidgetTester tester) async {
  await tester.runAsync(() async {
    // Found by icon, not label: the label now names whatever the device
    // will actually prompt with, so asserting one string here would tie
    // the test to a single device configuration.
    await tester.tap(find.byIcon(Icons.fingerprint));
  });

  // Poll rather than waiting a fixed interval: the first FFI open of the
  // suite also loads the native sqlite library, which takes noticeably
  // longer than subsequent ones, and a hard-coded delay tuned to the
  // warm case fails only on the first test to run.
  for (var attempt = 0; attempt < 40; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pumpAndSettle();
    if (find.byType(VaultHomeScreen).evaluate().isNotEmpty) return;
  }
  fail('The vault did not unlock within the allowed time.');
}

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory blobDir;

  setUp(() {
    blobDir = Directory.systemTemp.createTempSync('safekeep_open_test');
  });

  tearDown(() {
    if (blobDir.existsSync()) blobDir.deleteSync(recursive: true);
  });

  testWidgets('opening a document from the list renders the viewer', (
    tester,
  ) async {
    await tester.pumpWidget(
      App(
        config: const AppConfig(
          flavor: Flavor.development,
          appName: 'Safekeep Test',
        ),
        databasePath: inMemoryDatabasePath,
        blobDirectory: blobDir,
        keyManager: _UnlockedKeyManager(),
        biometricGate: _AvailableGate(),
        database: AppDatabase(opener: _InMemoryOpener()),
        repository: _OneDocumentRepository(),
      ),
    );

    await tester.pumpAndSettle();

    // Unlock through the button rather than the automatic prompt, which
    // fires from a post-frame callback and is not deterministic under
    // the test binding.
    await unlock(tester);

    expect(find.text('My passport'), findsOneWidget);

    await tester.tap(find.text('My passport'));
    await tester.pumpAndSettle();

    // Before the provider was hoisted above MaterialApp this threw
    // ProviderNotFoundException here, because the pushed route sat
    // outside the provider's subtree.
    expect(tester.takeException(), isNull);
    expect(find.byType(DocumentDetailScreen), findsOneWidget);
  });

  testWidgets('the viewer shows the document metadata', (tester) async {
    await tester.pumpWidget(
      App(
        config: const AppConfig(
          flavor: Flavor.development,
          appName: 'Safekeep Test',
        ),
        databasePath: inMemoryDatabasePath,
        blobDirectory: blobDir,
        keyManager: _UnlockedKeyManager(),
        biometricGate: _AvailableGate(),
        database: AppDatabase(opener: _InMemoryOpener()),
        repository: _OneDocumentRepository(),
      ),
    );
    await tester.pumpAndSettle();
    await unlock(tester);

    await tester.tap(find.text('My passport'));
    await tester.pumpAndSettle();

    expect(find.text('travel'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });
}
