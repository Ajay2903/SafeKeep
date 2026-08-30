import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:safekeep/core/logging/app_logger.dart';
import 'package:safekeep/data/mime_types.dart';
import 'package:safekeep/data/scanning/document_scanner.dart';

/// [DocumentScanner] backed by `cunning_document_scanner`.
///
/// That package wraps the platform's own scanner — ML Kit's on Android
/// (with a non-Play-Services fallback), Vision on iOS — rather than
/// shipping a custom edge detector. Edge detection, perspective
/// correction, and enhancement are all the OS's, which means less code to
/// audit and a capture UI users already recognise.
///
/// # Multi-page scans become one PDF
///
/// `asPdf: true` asks the platform to combine captured pages into a
/// single PDF. A multi-page passport or contract is one document to its
/// owner, and storing it as one blob keeps it that way — the alternative,
/// several images that must be kept together by convention, would leave
/// the vault holding pages nobody can reassemble.
///
/// # Temporary files
///
/// The platform scanner writes captures to app-private storage and
/// returns paths; there is no bytes-returning API. This adapter reads
/// them and then deletes them in a `finally`, so cleanup runs even if
/// reading throws. See [DocumentScanner] for why that window cannot be
/// closed entirely.
// NOTE: needs on-device verification. Scanner output quality — edge
// detection on a passport, legibility of small print, multi-page
// handling — cannot be judged from a unit test and must be checked on
// real hardware before this package is considered settled.
class CunningDocumentScannerAdapter implements DocumentScanner {
  const CunningDocumentScannerAdapter();

  @override
  Future<ScannedDocument?> scan({int maxPages = 20}) async {
    List<String>? paths;
    try {
      paths = await CunningDocumentScanner.getPictures(
        noOfPages: maxPages,
        // Camera only. Importing from the gallery is already a separate,
        // clearly-labelled action in the add-document sheet, and having
        // two routes to it would make the sheet's two options a lie.
        scannerSource: ScannerSource.camera,
        asPdf: true,
      );
    } on CunningDocumentScannerException catch (error) {
      // The message is the package's, not the platform's raw error, and
      // carries no document content — safe to surface.
      throw DocumentScanException(
        error.message,
        isPermissionDenied: error.code == 'permission_denied',
      );
    }

    // Null or empty means the user backed out. Not an error.
    if (paths == null || paths.isEmpty) return null;

    try {
      final file = File(paths.first);
      if (!file.existsSync()) {
        throw const DocumentScanException(
          'The scan could not be read back from the device.',
        );
      }

      final bytes = await file.readAsBytes();
      AppLogger.instance.info('Scan captured: ${paths.length} file(s)');

      return ScannedDocument(
        bytes: bytes,
        mimeType: MimeTypes.pdf,
        pageCount: paths.length,
      );
    } finally {
      // Runs even if reading failed, so a partial scan never leaves an
      // unencrypted page behind.
      await _cleanUp();
    }
  }

  Future<void> _cleanUp() async {
    try {
      await CunningDocumentScanner.cleanCache();
    } on CunningDocumentScannerException {
      // Deliberately swallowed. The document is already encrypted and
      // stored by this point, so a failed cleanup is not worth failing
      // the import over — but it is logged, because a scanner cache that
      // never clears is a plaintext leak worth noticing.
      AppLogger.instance.warning('Scanner cache could not be cleared');
    }
  }
}
