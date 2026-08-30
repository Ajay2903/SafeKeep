import 'dart:typed_data';

/// A scanned document, already in memory.
class ScannedDocument {
  const ScannedDocument({
    required this.bytes,
    required this.mimeType,
    required this.pageCount,
  });

  /// The scan, as bytes. Whatever the scanner wrote to disk has already
  /// been read and deleted by the time this exists.
  final Uint8List bytes;

  final String mimeType;

  /// Number of pages captured, for a sensible default title.
  final int pageCount;
}

/// Captures pages with the device camera and returns them as bytes.
///
/// # Why this is an interface
///
/// Scanner quality is the thing that decides whether this feature is
/// worth having, and it cannot be judged from a package's README — it
/// takes a real passport, in real lighting, on a real phone. So the
/// concrete package sits behind this interface from the start: if the
/// output turns out to be poor, swapping it costs one class rather than
/// unpicking scanning from the import flow, the UI, and the vault.
///
/// It also means the add-document flow can be tested without a camera.
///
/// # The plaintext-on-disk caveat
///
/// Both platforms' document scanners are OS components that write
/// captured pages to app-private storage and hand back file paths. There
/// is no API that returns bytes directly. Implementations therefore must:
///
/// 1. read the file into memory,
/// 2. delete the scanner's temporary files immediately,
/// 3. return only bytes.
///
/// This leaves a window — between capture and deletion — in which an
/// unencrypted page exists on disk. It is app-private and short-lived,
/// but deletion on flash storage does not reliably erase, so the data may
/// linger in unallocated blocks until reused. This is the one place in
/// the app where plaintext touches disk at all, it is a consequence of
/// using the platform scanner rather than a choice, and it is documented
/// rather than glossed over.
// ignore: one_member_abstracts
abstract interface class DocumentScanner {
  /// Opens the scanner UI.
  ///
  /// Returns null if the user cancels — a cancellation is a normal
  /// outcome, not an error.
  ///
  /// Throws [DocumentScanException] if the scan fails or camera
  /// permission is refused.
  Future<ScannedDocument?> scan({int maxPages});
}

/// A scan could not be completed.
class DocumentScanException implements Exception {
  const DocumentScanException(this.message, {this.isPermissionDenied = false});

  final String message;

  /// Whether the cause was a refused camera permission, which the UI
  /// should explain differently from a generic failure — the user can
  /// act on it.
  final bool isPermissionDenied;

  @override
  String toString() => 'DocumentScanException: $message';
}
