/// Maps a filename to a content type.
///
/// Deliberately a small allowlist rather than a general MIME database:
/// the vault only renders PDFs and common images, and anything else is
/// stored but shown as "cannot preview". A wrong guess here would send a
/// file to the wrong viewer, so unknown extensions get the generic type
/// rather than a plausible-looking one.
///
/// Detection is by extension rather than by sniffing magic bytes. The
/// bytes are available at import, so sniffing would be possible — but the
/// type is only used to choose a viewer, and both viewers already fail
/// gracefully on content they cannot render.
abstract final class MimeTypes {
  /// Used when the type is unknown. Documents with this type are stored
  /// and encrypted normally; they simply are not previewed.
  static const String unknown = 'application/octet-stream';

  static const String pdf = 'application/pdf';

  static const Map<String, String> _byExtension = {
    'pdf': pdf,
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'heic': 'image/heic',
    'heif': 'image/heif',
    'webp': 'image/webp',
    'gif': 'image/gif',
    'bmp': 'image/bmp',
    'tif': 'image/tiff',
    'tiff': 'image/tiff',
  };

  /// Extensions offered in the file picker.
  static List<String> get pickableExtensions => _byExtension.keys.toList();

  /// Returns the content type for [fileName], or [unknown].
  static String forFileName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot == -1 || dot == fileName.length - 1) return unknown;
    final extension = fileName.substring(dot + 1).toLowerCase();
    return _byExtension[extension] ?? unknown;
  }

  /// A reasonable default title from a filename: the name without its
  /// extension, so "passport-scan.pdf" pre-fills as "passport-scan".
  static String titleFromFileName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final base = dot == -1 ? fileName : fileName.substring(0, dot);
    return base.trim().isEmpty ? fileName : base.trim();
  }
}
