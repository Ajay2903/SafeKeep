import 'dart:io';
import 'dart:typed_data';

import 'package:safekeep/data/data_exceptions.dart';

/// Storage of encrypted document blobs on disk.
///
/// Callers pass **already-encrypted** bytes; this layer never sees
/// plaintext. That split is deliberate — it means the filesystem code has
/// no access to the cipher or to decrypted content, so a bug here cannot
/// leak a document.
///
/// # On "deleting the plaintext"
///
/// Plaintext is never written to disk in the first place. Bytes arrive in
/// memory, are encrypted, and only ciphertext is written. This is
/// stronger than writing a plaintext file and deleting it afterwards:
/// deletion on flash storage does not reliably erase anything, since
/// wear-levelling leaves the original blocks readable until they are
/// eventually reused.
abstract interface class DocumentFileStorage {
  /// Writes [encryptedBytes] under [fileName], replacing any existing
  /// blob with that name.
  Future<void> write(String fileName, Uint8List encryptedBytes);

  /// Reads the blob stored under [fileName].
  ///
  /// Throws [DocumentBlobMissingException] if it does not exist.
  Future<Uint8List> read(String fileName);

  /// Deletes the blob. Succeeds even if it is already absent, so a
  /// partially failed earlier delete can always be cleaned up.
  Future<void> delete(String fileName);

  /// Whether a blob exists under [fileName].
  Future<bool> exists(String fileName);
}

/// [DocumentFileStorage] backed by a directory on the local filesystem.
///
/// The directory is injected rather than resolved internally, so this
/// class has no dependency on `path_provider` and can be exercised
/// against a temporary directory in unit tests. Production resolves the
/// app-private documents directory via `VaultDirectory`.
class FileSystemDocumentFileStorage implements DocumentFileStorage {
  const FileSystemDocumentFileStorage({required Directory directory})
    : this._(directory);

  const FileSystemDocumentFileStorage._(this._directory);

  final Directory _directory;

  /// Characters permitted in a blob file name.
  ///
  /// Names are generated internally from random hex identifiers, so this
  /// should never reject legitimate input. It is enforced anyway: the
  /// name reaches a filesystem path, and a value containing `..` or a
  /// separator would let a caller read or overwrite files outside the
  /// vault directory. Cheap to validate, expensive to get wrong.
  static final RegExp _safeName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');

  @override
  Future<void> write(String fileName, Uint8List encryptedBytes) async {
    final file = _fileFor(fileName);
    await _directory.create(recursive: true);

    // Write to a temporary file and rename into place. `rename` is atomic
    // within a filesystem, so a crash mid-write leaves either the old
    // blob or the new one — never a truncated file that would fail
    // authentication and look like tampering.
    final temp = File('${file.path}.tmp');
    await temp.writeAsBytes(encryptedBytes, flush: true);
    await temp.rename(file.path);
  }

  @override
  Future<Uint8List> read(String fileName) async {
    final file = _fileFor(fileName);
    if (!file.existsSync()) {
      throw DocumentBlobMissingException(
        'No encrypted blob on disk for "$fileName".',
      );
    }
    return file.readAsBytes();
  }

  @override
  Future<void> delete(String fileName) async {
    final file = _fileFor(fileName);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  @override
  Future<bool> exists(String fileName) async => _fileFor(fileName).existsSync();

  File _fileFor(String fileName) {
    if (!_safeName.hasMatch(fileName)) {
      throw InvalidBlobNameException(
        'Blob name "$fileName" is not a permitted file name.',
      );
    }
    return File('${_directory.path}${Platform.pathSeparator}$fileName');
  }
}
