import 'package:meta/meta.dart';
import 'package:safekeep/domain/models/document.dart';
import 'package:safekeep/domain/models/document_category.dart';

/// State of the document list: everything loaded, plus the current
/// search and filter.
///
/// Filtering is a *derived* getter rather than a stored second list, so
/// the two can never disagree. The full set is what the cubit reloads;
/// [visible] is what the screen draws.
@immutable
class DocumentListState {
  const DocumentListState({
    this.isLoading = true,
    this.documents = const [],
    this.query = '',
    this.category,
    this.errorMessage,
  });

  final bool isLoading;

  /// Every document in the vault. Metadata only — no bytes are decrypted
  /// to build this.
  final List<Document> documents;

  final String query;

  /// Active category filter, or null for all categories.
  final DocumentCategory? category;

  final String? errorMessage;

  /// Whether the vault has no documents at all, as opposed to none
  /// matching the current search. The two need different empty states:
  /// one invites the first import, the other suggests clearing a filter.
  bool get isVaultEmpty => !isLoading && documents.isEmpty;

  bool get hasActiveFilter => query.isNotEmpty || category != null;

  /// Documents matching the current search and filter, newest first
  /// (the repository already orders them).
  List<Document> get visible {
    final trimmed = query.trim().toLowerCase();

    return documents.where((document) {
      if (category != null && document.category != category) return false;
      if (trimmed.isEmpty) return true;

      // Title and tags only. Notes are deliberately excluded: they are
      // free text people use for things like account numbers, and
      // surfacing a document because of a substring buried in a note
      // would make the match reason invisible to the user.
      if (document.title.toLowerCase().contains(trimmed)) return true;
      return document.tags.any(
        (tag) => tag.toLowerCase().contains(trimmed),
      );
    }).toList();
  }

  /// Categories that actually have documents, for building filter chips
  /// without offering an empty one.
  Set<DocumentCategory> get populatedCategories =>
      documents.map((d) => d.category).toSet();

  DocumentListState copyWith({
    bool? isLoading,
    List<Document>? documents,
    String? query,
    DocumentCategory? category,
    String? errorMessage,
    bool clearCategory = false,
    bool clearError = false,
  }) {
    return DocumentListState(
      isLoading: isLoading ?? this.isLoading,
      documents: documents ?? this.documents,
      query: query ?? this.query,
      category: clearCategory ? null : (category ?? this.category),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DocumentListState &&
      other.isLoading == isLoading &&
      other.query == query &&
      other.category == category &&
      other.errorMessage == errorMessage &&
      _sameDocuments(other.documents, documents);

  @override
  int get hashCode => Object.hash(
    isLoading,
    query,
    category,
    errorMessage,
    Object.hashAll(documents),
  );

  static bool _sameDocuments(List<Document> a, List<Document> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
