/// Failures raised by the data layer.
///
/// Same rule as the security module's exceptions: a `message` here may
/// reach logs, so it must never contain document contents, titles, notes,
/// or key material — only identifiers and the shape of what went wrong.
library;

/// Base type for data-layer failures.
sealed class DataException implements Exception {
  const DataException(this.message);

  final String message;

  /// Spelled out rather than derived from `runtimeType` so it survives
  /// minification in release builds.
  String get name;

  @override
  String toString() => '$name: $message';
}

/// A metadata record exists, but its encrypted blob is missing from disk.
///
/// Indicates the vault directory has been tampered with or partially
/// lost — a restore that copied the database but not the blobs, say.
/// Distinct from a decryption failure: the bytes are absent, not wrong.
final class DocumentBlobMissingException extends DataException {
  const DocumentBlobMissingException(super.message);

  @override
  String get name => 'DocumentBlobMissingException';
}

/// No document with the requested identifier exists.
final class DocumentNotFoundException extends DataException {
  const DocumentNotFoundException(super.message);

  @override
  String get name => 'DocumentNotFoundException';
}

/// A blob file name failed validation.
///
/// Names are generated internally, so this signals a programming error
/// or an attempt to traverse outside the vault directory.
final class InvalidBlobNameException extends DataException {
  const InvalidBlobNameException(super.message);

  @override
  String get name => 'InvalidBlobNameException';
}
