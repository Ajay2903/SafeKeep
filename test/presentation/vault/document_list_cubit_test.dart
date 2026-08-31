import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safekeep/data/data_exceptions.dart';
import 'package:safekeep/domain/models/document.dart';
import 'package:safekeep/domain/models/document_category.dart';
import 'package:safekeep/domain/repositories/document_repository.dart';
import 'package:safekeep/presentation/vault/document_list_cubit.dart';
import 'package:safekeep/presentation/vault/document_list_state.dart';
import 'package:safekeep/security/security_exceptions.dart';

Document _doc({
  required String id,
  required String title,
  DocumentCategory category = DocumentCategory.identity,
  List<String> tags = const [],
}) {
  return Document(
    id: id,
    title: title,
    category: category,
    tags: tags,
    createdAt: DateTime.utc(2026),
    modifiedAt: DateTime.utc(2026),
    version: 1,
    blobFileName: '$id.blob',
    plaintextSizeBytes: 100,
    mimeType: 'application/pdf',
  );
}

class _FakeRepository implements DocumentRepository {
  List<Document> documents = [];
  bool throwLocked = false;
  bool throwOnDelete = false;
  final List<String> deleted = [];

  @override
  Future<List<Document>> listDocuments() async {
    if (throwLocked) throw const VaultLockedException();
    return documents;
  }

  @override
  Future<void> deleteAllDocuments() async {}

  @override
  Future<void> deleteDocument(String id) async {
    if (throwOnDelete) {
      throw const DocumentNotFoundException('nope');
    }
    deleted.add(id);
    documents = documents.where((d) => d.id != id).toList();
  }

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

  @override
  Future<Document?> getDocument(String id) async => null;

  @override
  Future<Uint8List> openDocument(String id) async => Uint8List(0);

  @override
  Future<Document> updateDocument(Document document) async => document;
}

void main() {
  late _FakeRepository repository;

  setUp(() => repository = _FakeRepository());

  DocumentListCubit build() => DocumentListCubit(repository: repository);

  group('load', () {
    blocTest<DocumentListCubit, DocumentListState>(
      'loads documents and stops loading',
      build: build,
      setUp: () => repository.documents = [
        _doc(id: 'a', title: 'Passport'),
      ],
      act: (cubit) => cubit.load(),
      verify: (cubit) {
        expect(cubit.state.isLoading, isFalse);
        expect(cubit.state.documents.length, 1);
      },
    );

    test('an empty vault is distinguishable from an empty search', () async {
      final cubit = build();
      await cubit.load();

      // These need different empty states: one invites a first import,
      // the other suggests clearing a filter.
      expect(cubit.state.isVaultEmpty, isTrue);

      repository.documents = [_doc(id: 'a', title: 'Passport')];
      await cubit.load();
      cubit.search('nothing matches this');

      expect(cubit.state.isVaultEmpty, isFalse);
      expect(cubit.state.visible, isEmpty);
      await cubit.close();
    });

    test('a mid-load lock does not surface an error', () async {
      // The gate is already tearing the screen down; an error banner
      // would flash on the way out.
      repository.throwLocked = true;
      final cubit = build();

      await cubit.load();

      expect(cubit.state.errorMessage, isNull);
      expect(cubit.state.isLoading, isFalse);
      await cubit.close();
    });
  });

  group('search', () {
    late DocumentListCubit cubit;

    setUp(() async {
      repository.documents = [
        _doc(id: 'a', title: 'Passport', tags: ['travel', 'urgent']),
        _doc(
          id: 'b',
          title: 'Car insurance',
          category: DocumentCategory.insurance,
          tags: ['vehicle'],
        ),
        _doc(
          id: 'c',
          title: 'Tax return 2025',
          category: DocumentCategory.tax,
        ),
      ];
      cubit = build();
      await cubit.load();
    });

    tearDown(() => cubit.close());

    test('matches titles case-insensitively', () {
      cubit.search('passport');
      expect(cubit.state.visible.map((d) => d.id), ['a']);

      cubit.search('PASSPORT');
      expect(cubit.state.visible.map((d) => d.id), ['a']);
    });

    test('matches partial titles', () {
      cubit.search('insur');
      expect(cubit.state.visible.map((d) => d.id), ['b']);
    });

    test('matches tags', () {
      cubit.search('vehicle');
      expect(cubit.state.visible.map((d) => d.id), ['b']);
    });

    test('ignores surrounding whitespace', () {
      cubit.search('  passport  ');
      expect(cubit.state.visible.map((d) => d.id), ['a']);
    });

    test('an empty query shows everything', () {
      cubit
        ..search('passport')
        ..clearSearch();
      expect(cubit.state.visible.length, 3);
    });

    test('a non-matching query yields nothing', () {
      cubit.search('zzzz');
      expect(cubit.state.visible, isEmpty);
    });
  });

  group('category filter', () {
    late DocumentListCubit cubit;

    setUp(() async {
      repository.documents = [
        _doc(id: 'a', title: 'Passport'),
        _doc(
          id: 'b',
          title: 'Car insurance',
          category: DocumentCategory.insurance,
        ),
      ];
      cubit = build();
      await cubit.load();
    });

    tearDown(() => cubit.close());

    test('narrows to one category', () {
      cubit.filterByCategory(DocumentCategory.insurance);
      expect(cubit.state.visible.map((d) => d.id), ['b']);
    });

    test('selecting the active category again clears the filter', () {
      cubit
        ..filterByCategory(DocumentCategory.insurance)
        ..filterByCategory(DocumentCategory.insurance);

      expect(cubit.state.category, isNull);
      expect(cubit.state.visible.length, 2);
    });

    test('null clears the filter', () {
      cubit
        ..filterByCategory(DocumentCategory.insurance)
        ..filterByCategory(null);

      expect(cubit.state.visible.length, 2);
    });

    test('combines with search', () {
      cubit
        ..filterByCategory(DocumentCategory.insurance)
        ..search('passport');

      // Passport is an identity document, so the filter excludes it even
      // though the title matches.
      expect(cubit.state.visible, isEmpty);
    });

    test('populatedCategories omits categories with no documents', () {
      expect(cubit.state.populatedCategories, {
        DocumentCategory.identity,
        DocumentCategory.insurance,
      });
    });
  });

  group('delete', () {
    test('removes the document and reloads', () async {
      repository.documents = [
        _doc(id: 'a', title: 'Passport'),
        _doc(id: 'b', title: 'Licence'),
      ];
      final cubit = build();
      await cubit.load();

      await cubit.deleteDocument('a');

      expect(repository.deleted, ['a']);
      expect(cubit.state.documents.map((d) => d.id), ['b']);
      await cubit.close();
    });

    test('surfaces a message when deletion fails', () async {
      repository
        ..documents = [_doc(id: 'a', title: 'Passport')]
        ..throwOnDelete = true;
      final cubit = build();
      await cubit.load();

      await cubit.deleteDocument('a');

      expect(cubit.state.errorMessage, isNotNull);
      await cubit.close();
    });
  });
}
