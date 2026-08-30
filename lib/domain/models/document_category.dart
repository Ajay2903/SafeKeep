/// The kinds of document the vault organises.
///
/// Stored in the database by [storageValue], not by index: reordering or
/// inserting enum values must never silently re-categorise existing rows.
enum DocumentCategory {
  identity('identity'),
  license('license'),
  contract('contract'),
  insurance('insurance'),
  medical('medical'),
  tax('tax'),
  other('other');

  const DocumentCategory(this.storageValue);

  /// Stable string written to the database. Never change these.
  final String storageValue;

  /// Parses a value previously written by [storageValue].
  ///
  /// Unknown values fall back to [other] rather than throwing: a row
  /// written by a newer build with a category this one does not know
  /// should still be readable, since the document itself is intact.
  static DocumentCategory fromStorage(String value) {
    for (final category in DocumentCategory.values) {
      if (category.storageValue == value) return category;
    }
    return DocumentCategory.other;
  }
}
