import 'dart:typed_data';

import 'package:safekeep/security/encryption/encryption_key_source.dart';
import 'package:safekeep/security/security_exceptions.dart';

/// Owns the vault's key material and its lock/unlock lifecycle.
///
/// # Why this replaced the Phase 0 shape
///
/// The Phase 0 stub was `getOrCreateKey(keyId)`, documented as generating
/// and persisting a random key on first use. That contract is
/// fundamentally incompatible with a zero-knowledge, passphrase-derived
/// vault:
///
///   * A randomly generated key is not reproducible from the passphrase,
///     so "forget your passphrase and the data is gone" would not hold —
///     and neither would restoring a vault on a second device.
///   * There was nowhere to put the passphrase, the biometric gate, or
///     the locked/unlocked distinction that the whole design depends on.
///   * Silently creating a key on first call would mask "no vault exists
///     yet" as success, which for a vault is a dangerous default.
///
/// The crypto-erase intent of the old `deleteKey` survives as
/// [deleteVault].
///
/// # Lifecycle
///
/// ```text
/// setUpVault(passphrase)        once, at first run
///        │
///        ▼
///   [ unlocked ]  ──lock()/auto-lock──►  [ locked ]
///        ▲                                   │
///        └── unlockWithPassphrase() ◄─────────┤
///            unlockWithBiometrics()  ◄────────┘
/// ```
///
/// While locked, [encryptionKeyFor] throws [VaultLockedException]; the key
/// is not held anywhere in the process.
abstract interface class KeyManager implements EncryptionKeySource {
  /// Whether a vault has been set up on this device.
  Future<bool> isInitialized();

  /// Whether key material is currently held in memory.
  bool get isUnlocked;

  /// Returns the SQLCipher key for the metadata database.
  ///
  /// A sibling of the document encryption key, derived from the same
  /// master key under its own HKDF label. Throws [VaultLockedException]
  /// while the vault is locked.
  Future<Uint8List> databaseKey();

  /// Creates the vault: derives key material from [passphrase], persists
  /// the salt, KDF parameters, verifier, and encryption key, and leaves
  /// the vault unlocked (the user has just proven they know the
  /// passphrase).
  ///
  /// Throws [VaultAlreadyInitializedException] if a vault already exists.
  /// Overwriting would destroy the key and therefore every document
  /// encrypted under it, so it is refused rather than silently handled.
  Future<void> setUpVault({required String passphrase});

  /// Checks [passphrase] against the stored verifier **without**
  /// unlocking and without needing any document to decrypt.
  ///
  /// Returns `true` if correct. Used for re-authentication and for
  /// setting up an existing vault on a new device.
  ///
  /// Throws [VaultNotInitializedException] if no vault exists.
  Future<bool> verifyPassphrase(String passphrase);

  /// Verifies [passphrase] and, if correct, loads the key for this
  /// session. Returns `false` on a wrong passphrase, leaving the vault
  /// locked.
  ///
  /// Works even when only the salt, KDF parameters, and verifier are
  /// present — the key is re-derived rather than read from storage — which
  /// is what makes restoring a backup onto a new device possible.
  ///
  /// Known gap: on such a device the derived key is held for the session
  /// only and is not written to secure storage, so
  /// [unlockWithBiometrics] will not work there until the vault is
  /// explicitly adopted on that device.
  // TODO(phase-backup): add adoptOnThisDevice() to persist the re-derived
  // key after a restore, so biometric unlock works on the new device.
  // Belongs with the backup/restore phase, not the core crypto layer.
  Future<bool> unlockWithPassphrase(String passphrase);

  /// Unlocks using biometrics or the device credential.
  ///
  /// Returns `false` if the user cancels or authentication fails, leaving
  /// the vault locked. The key is only read out of secure storage after
  /// the gate reports success.
  Future<bool> unlockWithBiometrics();

  /// Clears key material from memory and returns to the locked state.
  ///
  /// Safe to call when already locked.
  void lock();

  /// Permanently deletes the vault: key, salt, verifier, and parameters.
  ///
  /// This is a cryptographic erase — every document encrypted under the
  /// key becomes unrecoverable, whether or not the ciphertext still
  /// exists. There is no undo.
  Future<void> deleteVault();
}
