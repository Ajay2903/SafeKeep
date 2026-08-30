import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safekeep/app/app.dart';
import 'package:safekeep/core/config/app_config.dart';
import 'package:safekeep/core/config/flavor.dart';
import 'package:safekeep/data/database/app_database.dart';
import 'package:safekeep/data/database/database_opener.dart';
import 'package:safekeep/data/mime_types.dart';
import 'package:safekeep/data/scanning/document_scanner.dart';
import 'package:safekeep/domain/models/document.dart';
import 'package:safekeep/domain/models/document_category.dart';
import 'package:safekeep/domain/repositories/document_repository.dart';
import 'package:safekeep/presentation/vault/document_form_screen.dart';
import 'package:safekeep/presentation/vault/vault_home_screen.dart';
import 'package:safekeep/security/auth/biometric_gate.dart';
import 'package:safekeep/security/key_management/key_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The scan path, exercised without a camera.
///
/// This is the payoff for putting the scanner behind an interface: the
/// whole flow — sheet, capture, metadata form, encrypt-and-store — is
/// testable, and the concrete package can be swapped without any of
/// these tests changing.

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

/// Stands in for the camera.
class _FakeScanner implements DocumentScanner {
  _FakeScanner({this.result, this.error});

  ScannedDocument? result;
  DocumentScanException? error;
  int scanCalls = 0;

  @override
  Future<ScannedDocument?> scan({int maxPages = 20}) async {
    scanCalls++;
    final failure = error;
    if (failure != null) throw failure;
    return result;
  }
}

class _RecordingRepository implements DocumentRepository {
  final List<Document> stored = [];
  Uint8List? lastBytes;
  String? lastMimeType;

  @override
  Future<Document> addDocument({
    required Uint8List bytes,
    required String title,
    required DocumentCategory category,
    required String mimeType,
    List<String> tags = const [],
    String? notes,
    DateTime? expiresAt,
  }) async {
    lastBytes = bytes;
    lastMimeType = mimeType;
    final document = Document(
      id: 'scanned-${stored.length}',
      title: title,
      category: category,
      tags: tags,
      notes: notes,
      expiresAt: expiresAt,
      createdAt: DateTime.utc(2026),
      modifiedAt: DateTime.utc(2026),
      version: 1,
      blobFileName: 'scanned.blob',
      plaintextSizeBytes: bytes.length,
      mimeType: mimeType,
    );
    stored.add(document);
    return document;
  }

  @override
  Future<List<Document>> listDocuments() async => stored;

  @override
  Future<Document?> getDocument(String id) async => null;

  @override
  Future<Uint8List> openDocument(String id) async => Uint8List(0);

  @override
  Future<void> deleteDocument(String id) async {}

  @override
  Future<Document> updateDocument(Document document) async => document;
}

Future<void> unlock(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.tap(find.text('Unlock with biometrics'));
  });
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
  late _RecordingRepository repository;

  setUp(() {
    blobDir = Directory.systemTemp.createTempSync('safekeep_scan_test');
    repository = _RecordingRepository();
  });

  tearDown(() {
    if (blobDir.existsSync()) blobDir.deleteSync(recursive: true);
  });

  Widget buildApp(DocumentScanner scanner) {
    return App(
      config: const AppConfig(
        flavor: Flavor.development,
        appName: 'Safekeep Test',
      ),
      databasePath: inMemoryDatabasePath,
      blobDirectory: blobDir,
      keyManager: _UnlockedKeyManager(),
      biometricGate: _AvailableGate(),
      database: AppDatabase(opener: _InMemoryOpener()),
      repository: repository,
      scanner: scanner,
    );
  }

  final scanBytes = Uint8List.fromList(List.filled(2048, 7));

  ScannedDocument scanned({int pages = 1}) => ScannedDocument(
    bytes: scanBytes,
    mimeType: MimeTypes.pdf,
    pageCount: pages,
  );

  group('add-document sheet', () {
    testWidgets('offers both scanning and importing', (tester) async {
      await tester.pumpWidget(buildApp(_FakeScanner()));
      await tester.pumpAndSettle();
      await unlock(tester);

      await tester.tap(find.text('Add your first document'));
      await tester.pumpAndSettle();

      expect(find.text('Scan with camera'), findsOneWidget);
      expect(find.text('Import a file'), findsOneWidget);
      // The reassurance that matters most, stated at the point of action.
      expect(
        find.textContaining('encrypted before it is stored'),
        findsOneWidget,
      );
    });
  });

  group('scanning', () {
    testWidgets('a scan reaches the metadata form', (tester) async {
      final scanner = _FakeScanner(result: scanned());
      await tester.pumpWidget(buildApp(scanner));
      await tester.pumpAndSettle();
      await unlock(tester);

      await tester.tap(find.text('Add your first document'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan with camera'));
      await tester.pumpAndSettle();

      expect(scanner.scanCalls, 1);
      expect(find.byType(DocumentFormScreen), findsOneWidget);
      expect(find.textContaining('Scanned document'), findsOneWidget);
    });

    testWidgets('a multi-page scan is described as pages', (tester) async {
      await tester.pumpWidget(
        buildApp(_FakeScanner(result: scanned(pages: 4))),
      );
      await tester.pumpAndSettle();
      await unlock(tester);

      await tester.tap(find.text('Add your first document'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan with camera'));
      await tester.pumpAndSettle();

      expect(find.textContaining('4 scanned pages'), findsOneWidget);
    });

    testWidgets('a completed scan is encrypted and stored as a PDF', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp(_FakeScanner(result: scanned())));
      await tester.pumpAndSettle();
      await unlock(tester);

      await tester.tap(find.text('Add your first document'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan with camera'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Passport',
      );
      await tester.pumpAndSettle();

      // The form is a lazily-built ListView, so the submit button is not
      // in the tree until scrolled into view on a short viewport.
      await tester.scrollUntilVisible(
        find.text('Encrypt and save'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Encrypt and save'));
      await tester.pumpAndSettle();

      // The scanner is just another source of bytes: they arrive at the
      // same repository call an imported file would.
      expect(repository.stored.length, 1);
      expect(repository.stored.single.title, 'Passport');
      expect(repository.lastBytes, scanBytes);
      expect(repository.lastMimeType, MimeTypes.pdf);
    });

    testWidgets('cancelling the scanner stores nothing', (tester) async {
      // Backing out of the camera is a normal action, not an error.
      await tester.pumpWidget(buildApp(_FakeScanner()));
      await tester.pumpAndSettle();
      await unlock(tester);

      await tester.tap(find.text('Add your first document'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan with camera'));
      await tester.pumpAndSettle();

      expect(find.byType(DocumentFormScreen), findsNothing);
      expect(repository.stored, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a refused camera permission is explained, not just failed', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(
          _FakeScanner(
            error: const DocumentScanException(
              'denied',
              isPermissionDenied: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await unlock(tester);

      await tester.tap(find.text('Add your first document'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan with camera'));
      await tester.pumpAndSettle();

      // Actionable: the user can go and fix this.
      expect(find.textContaining('Camera access'), findsOneWidget);
      expect(repository.stored, isEmpty);
    });

    testWidgets('a generic scan failure surfaces a message', (tester) async {
      await tester.pumpWidget(
        buildApp(_FakeScanner(error: const DocumentScanException('boom'))),
      );
      await tester.pumpAndSettle();
      await unlock(tester);

      await tester.tap(find.text('Add your first document'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan with camera'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('scan could not be completed'),
        findsOneWidget,
      );
      expect(repository.stored, isEmpty);
    });
  });
}
