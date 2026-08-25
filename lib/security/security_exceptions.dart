/// Failures raised by the security module.
///
/// # Rule for every exception in this file
///
/// A `message` here may be surfaced in logs, crash reports, or (indirectly)
/// UI. It must therefore **never** embed plaintext, key material,
/// passphrases, salts-with-context, or any decrypted bytes — only the
/// *shape* of what went wrong. See the class-level doc on `AppLogger`
/// (`lib/core/logging/app_logger.dart`) for the full rule.
///
/// Deliberately no `originalError` field: wrapping a third-party crypto
/// exception verbatim risks leaking internal state into logs, so callers
/// get a clean, self-authored message instead.
library;

/// Base type for everything this module throws.
///
/// Sealed so that exhaustive `switch` over failure modes is possible at
/// call sites, and so no code outside this module can invent a new
/// security failure type.
sealed class SecurityException implements Exception {
  const SecurityException(this.message);

  final String message;

  /// Stable, human-readable name for this failure.
  ///
  /// Spelled out explicitly rather than derived from `runtimeType` so that
  /// it survives minification in release builds and stays stable in logs.
  String get name;

  @override
  String toString() => '$name: $message';
}

/// The stored blob is not a well-formed SafeKeep encrypted blob.
///
/// Raised *before* any decryption is attempted — e.g. the blob is shorter
/// than the fixed header, or carries a format version this build doesn't
/// understand. Distinct from [DecryptionAuthenticationException]: this one
/// means "this isn't our format", not "this has been tampered with".
final class MalformedCiphertextException extends SecurityException {
  const MalformedCiphertextException(super.message);

  @override
  String get name => 'MalformedCiphertextException';
}

/// The AES-GCM authentication tag did not verify.
///
/// This means one of: the ciphertext was modified, the blob was truncated
/// or corrupted, or the wrong key was supplied. These are deliberately
/// **not** distinguished — telling an attacker which of those happened
/// leaks information, and no caller can safely act on the difference.
///
/// Callers must treat this as fatal for the affected document. Never
/// retry, never fall back to returning partial or unverified plaintext.
final class DecryptionAuthenticationException extends SecurityException {
  const DecryptionAuthenticationException([
    super.message =
        'Authentication failed: the data was modified, '
        'corrupted, or encrypted under a different key.',
  ]);

  @override
  String get name => 'DecryptionAuthenticationException';
}

/// Key material was requested while the vault is locked.
///
/// Indicates a programming error at the call site — callers must unlock
/// (and therefore pass the biometric gate) before asking for the key.
final class VaultLockedException extends SecurityException {
  const VaultLockedException([
    super.message =
        'The vault is locked. Unlock it before using key '
        'material.',
  ]);

  @override
  String get name => 'VaultLockedException';
}

/// An operation required an initialized vault, but none exists yet.
final class VaultNotInitializedException extends SecurityException {
  const VaultNotInitializedException([
    super.message = 'No vault has been set up on this device.',
  ]);

  @override
  String get name => 'VaultNotInitializedException';
}

/// Vault setup was attempted when a vault already exists.
///
/// Overwriting it would destroy the existing key and therefore every
/// document encrypted under it, so this is refused rather than handled.
final class VaultAlreadyInitializedException extends SecurityException {
  const VaultAlreadyInitializedException([
    super.message =
        'A vault already exists on this device. Delete it '
        'before setting up a new one.',
  ]);

  @override
  String get name => 'VaultAlreadyInitializedException';
}

/// Biometric or device-credential authentication did not succeed.
final class AuthenticationRequiredException extends SecurityException {
  const AuthenticationRequiredException([
    super.message =
        'Biometric or device-credential authentication was '
        'not completed.',
  ]);

  @override
  String get name => 'AuthenticationRequiredException';
}
