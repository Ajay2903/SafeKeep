import 'package:flutter_test/flutter_test.dart';
import 'package:safekeep/domain/models/document.dart';
import 'package:safekeep/domain/models/document_category.dart';

Document _document({
  String id = 'doc-1',
  String title = 'Passport',
  DocumentCategory category = DocumentCategory.identity,
  List<String> tags = const ['travel'],
  String? notes,
  DateTime? expiresAt,
  int version = 1,
}) {
  return Document(
    id: id,
    title: title,
    category: category,
    tags: tags,
    notes: notes,
    expiresAt: expiresAt,
    createdAt: DateTime.utc(2026),
    modifiedAt: DateTime.utc(2026),
    version: version,
    blobFileName: '$id.blob',
    plaintextSizeBytes: 1024,
    mimeType: 'application/pdf',
  );
}

void main() {
  group('DocumentCategory', () {
    test('round-trips through its storage value', () {
      for (final category in DocumentCategory.values) {
        expect(
          DocumentCategory.fromStorage(category.storageValue),
          category,
        );
      }
    });

    test('storage values are stable strings, not indices', () {
      // Guards against someone reordering the enum: these strings are a
      // persisted format and must not change.
      expect(DocumentCategory.identity.storageValue, 'identity');
      expect(DocumentCategory.license.storageValue, 'license');
      expect(DocumentCategory.contract.storageValue, 'contract');
      expect(DocumentCategory.insurance.storageValue, 'insurance');
      expect(DocumentCategory.medical.storageValue, 'medical');
      expect(DocumentCategory.tax.storageValue, 'tax');
      expect(DocumentCategory.other.storageValue, 'other');
    });

    test('an unknown value falls back to other rather than throwing', () {
      // A row written by a newer build must stay readable — the document
      // itself is intact even if its category is unfamiliar.
      expect(
        DocumentCategory.fromStorage('passport-v2'),
        DocumentCategory.other,
      );
      expect(DocumentCategory.fromStorage(''), DocumentCategory.other);
    });
  });

  group('Document', () {
    test('equality compares fields, not identity', () {
      expect(_document(), _document());
      expect(_document().hashCode, _document().hashCode);
    });

    test('differs when any field differs', () {
      expect(_document(), isNot(_document(title: 'Licence')));
      expect(_document(), isNot(_document(version: 2)));
      expect(_document(), isNot(_document(tags: ['travel', 'urgent'])));
    });

    test('toString leaks no user content', () {
      final document = _document(
        title: 'MY-SECRET-PASSPORT',
        tags: ['SENSITIVE-TAG'],
        notes: 'SECRET-NOTE',
      );

      // Models end up in logs and error messages; title, tags, and notes
      // are document contents.
      final text = document.toString();
      expect(text, isNot(contains('MY-SECRET-PASSPORT')));
      expect(text, isNot(contains('SENSITIVE-TAG')));
      expect(text, isNot(contains('SECRET-NOTE')));
      expect(text, contains('doc-1'), reason: 'id is safe to log');
    });

    test('copyWith changes only what is asked', () {
      final updated = _document().copyWith(title: 'Renewed passport');

      expect(updated.title, 'Renewed passport');
      expect(updated.id, _document().id);
      expect(updated.category, _document().category);
      expect(updated.blobFileName, _document().blobFileName);
    });

    test('copyWith can clear nullable fields explicitly', () {
      final withValues = _document(
        notes: 'a note',
        expiresAt: DateTime.utc(2030),
      );

      // Passing null to copyWith cannot distinguish "unset" from "leave
      // alone", hence the explicit clear flags.
      expect(withValues.copyWith(clearNotes: true).notes, isNull);
      expect(
        withValues.copyWith(clearExpiresAt: true).expiresAt,
        isNull,
      );
      expect(withValues.copyWith().notes, 'a note');
    });

    test('isExpiredAt compares against the given moment', () {
      final expiring = _document(expiresAt: DateTime.utc(2026, 6));

      expect(expiring.isExpiredAt(DateTime.utc(2026, 7)), isTrue);
      expect(expiring.isExpiredAt(DateTime.utc(2026, 5)), isFalse);
    });

    test('a document with no expiry is never expired', () {
      expect(_document().isExpiredAt(DateTime.utc(2999)), isFalse);
    });
  });
}
