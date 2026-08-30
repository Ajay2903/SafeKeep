import 'package:meta/meta.dart';
import 'package:safekeep/domain/models/document_category.dart';

/// Metadata describing one stored document.
///
/// This is **metadata only** — it never carries the document's bytes.
/// Those live encrypted on disk and are fetched separately, so that
/// listing a vault of hundreds of documents does not decrypt any of them.
///
/// Plain Dart with no Flutter or storage dependencies: the domain layer
/// must stay independent of how any of this is persisted.
@immutable
class Document {
  const Document({
    required this.id,
    required this.title,
    required this.category,
    required this.tags,
    required this.createdAt,
    required this.modifiedAt,
    required this.version,
    required this.blobFileName,
    required this.plaintextSizeBytes,
    required this.mimeType,
    this.notes,
    this.expiresAt,
  });

  /// Opaque unique identifier, also used as the AES-GCM associated data
  /// binding the document's blob to this record (see `EncryptedBlob`).
  final String id;

  final String title;
  final DocumentCategory category;
  final List<String> tags;
  final String? notes;

  /// When the document itself expires (a passport's expiry, say), not
  /// when the record does. Null when it never expires.
  final DateTime? expiresAt;

  final DateTime createdAt;
  final DateTime modifiedAt;

  /// Monotonic revision counter, incremented on every metadata change.
  ///
  /// Exists for the later sync phase: comparing versions across devices
  /// is how a conflict is detected. Nothing uses it yet, but writing it
  /// from the start avoids a migration that would have to invent version
  /// numbers for pre-existing rows.
  final int version;

  /// Filename of the encrypted blob within the vault directory.
  ///
  /// Stored rather than derived from [id] so that changing the naming
  /// scheme later cannot orphan existing documents — the same reasoning
  /// that applies to persisting KDF parameters per vault.
  final String blobFileName;

  /// Size of the *decrypted* document, for display without decrypting.
  final int plaintextSizeBytes;

  /// Content type of the stored bytes, e.g. `application/pdf`.
  ///
  /// Recorded at import so the viewer knows how to render a document
  /// without decrypting it first and sniffing the bytes — which would
  /// mean decrypting every document just to build a list.
  final String mimeType;

  /// Whether this document renders in the PDF viewer.
  bool get isPdf => mimeType == 'application/pdf';

  /// Whether this document renders as an image.
  bool get isImage => mimeType.startsWith('image/');

  /// Whether this document has an expiry date already in the past.
  bool isExpiredAt(DateTime now) {
    final expiry = expiresAt;
    return expiry != null && expiry.isBefore(now);
  }

  Document copyWith({
    String? title,
    DocumentCategory? category,
    List<String>? tags,
    String? notes,
    DateTime? expiresAt,
    DateTime? modifiedAt,
    int? version,
    bool clearNotes = false,
    bool clearExpiresAt = false,
  }) {
    return Document(
      id: id,
      title: title ?? this.title,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      notes: clearNotes ? null : (notes ?? this.notes),
      expiresAt: clearExpiresAt ? null : (expiresAt ?? this.expiresAt),
      createdAt: createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      version: version ?? this.version,
      blobFileName: blobFileName,
      plaintextSizeBytes: plaintextSizeBytes,
      mimeType: mimeType,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Document &&
      other.id == id &&
      other.title == title &&
      other.category == category &&
      _sameTags(other.tags, tags) &&
      other.notes == notes &&
      other.expiresAt == expiresAt &&
      other.createdAt == createdAt &&
      other.modifiedAt == modifiedAt &&
      other.version == version &&
      other.blobFileName == blobFileName &&
      other.plaintextSizeBytes == plaintextSizeBytes &&
      other.mimeType == mimeType;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    category,
    Object.hashAll(tags),
    notes,
    expiresAt,
    createdAt,
    modifiedAt,
    version,
    blobFileName,
    plaintextSizeBytes,
    mimeType,
  );

  /// Deliberately omits every user-supplied field.
  ///
  /// A model's `toString` ends up in logs and error messages, and title,
  /// notes, and tags are document contents. Only the id and non-sensitive
  /// bookkeeping appear here. See `AppLogger` for the full rule.
  @override
  String toString() => 'Document(id: $id, version: $version)';

  static bool _sameTags(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
