import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Resolves the directory encrypted blobs are stored in.
///
/// Split out from `FileSystemDocumentFileStorage` so that the storage
/// class itself has no `path_provider` dependency and stays unit-testable
/// against a temporary directory. This wrapper needs a platform channel
/// and can only be verified on a device.
///
/// The application documents directory is app-private on both Android and
/// iOS: other apps cannot read it without defeating the OS sandbox.
/// Blobs are encrypted regardless — the sandbox is a second layer, not
/// the protection.
// NOTE: needs on-device verification; path_provider cannot run under
// flutter test.
abstract final class VaultDirectory {
  /// Subdirectory holding encrypted document blobs.
  static const String directoryName = 'vault';

  /// Returns (creating if needed) the vault blob directory.
  static Future<Directory> resolve() async {
    final documents = await getApplicationDocumentsDirectory();
    final vault = Directory(
      '${documents.path}${Platform.pathSeparator}$directoryName',
    );
    if (!vault.existsSync()) {
      await vault.create(recursive: true);
    }
    return vault;
  }
}
