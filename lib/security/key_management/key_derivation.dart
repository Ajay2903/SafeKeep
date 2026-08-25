import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:safekeep/security/key_management/kdf_parameters.dart';

/// Derives the vault's key material from a user passphrase.
///
/// # Algorithm: Argon2id
///
/// Argon2id (RFC 9106) won the Password Hashing Competition and is OWASP's
/// first recommendation. It is chosen here over PBKDF2-HMAC-SHA256 because
/// it is *memory-hard*: PBKDF2 is trivially parallelised on GPUs and ASICs
/// at almost no cost per additional guess, whereas Argon2id forces an
/// attacker to allocate [KdfParameters.memoryKib] of RAM per concurrent
/// guess, which is what actually limits large-scale offline cracking.
///
/// The `package:cryptography` implementation is pure Dart. It is verified
/// against the official RFC 9106 section 5.3 test vector in
/// `test/security/key_management/key_derivation_test.dart` — that test is
/// the reason we can trust this implementation, and it must never be
/// deleted or skipped.
///
/// # Two keys from one passphrase, via HKDF
///
/// The Argon2id output is never used directly. It is expanded with
/// HKDF-SHA256 into two independent keys under distinct `info` labels:
///
/// ```text
/// masterKey     = Argon2id(passphrase, salt, params)
/// encryptionKey = HKDF-SHA256(masterKey, info: "safekeep:v1:encryption")
/// verifier      = HKDF-SHA256(masterKey, info: "safekeep:v1:verification")
/// ```
///
/// The point of this domain separation is that the *verifier is persisted*
/// (it is how a re-entered passphrase is checked) while the encryption key
/// is the thing being protected. Because HKDF is one-way and the two
/// labels are distinct, an attacker who reads the stored verifier learns
/// nothing about the encryption key. Had the raw master key been stored as
/// its own verifier, reading it would have handed over the encryption key
/// outright.
///
/// Note this does not protect against *guessing*: anyone with the salt and
/// the verifier can test passphrase guesses offline. That is inherent to
/// any offline vault, and is exactly what the Argon2id cost is defending.
///
/// # Threading
///
/// Derivation takes on the order of a second on a phone, so [deriveKeys]
/// runs Argon2id on a background isolate via [Isolate.run]. Doing this
/// inside the KDF rather than at call sites means no caller can forget to,
/// and the platform thread can never be blocked long enough to trigger an
/// Android ANR (5 s).
class KeyDerivation {
  const KeyDerivation();

  /// Salt length in bytes.
  ///
  /// 16 bytes (128 bits) as recommended by RFC 9106. The salt is not
  /// secret — it is stored in the clear next to the vault — its only job
  /// is to be unique per vault so that an attacker cannot build one
  /// rainbow table and reuse it against many users, and so two users with
  /// the same passphrase get different keys.
  static const int saltLength = 16;

  /// HKDF `info` labels. Changing either of these strings changes every
  /// derived key and would orphan existing vaults, so they are versioned
  /// and must be treated as a wire format.
  static const String _encryptionInfo = 'safekeep:v1:encryption';
  static const String _verificationInfo = 'safekeep:v1:verification';

  /// Generates a fresh random salt using a cryptographically secure RNG.
  ///
  /// [Random.secure] is backed by the platform CSPRNG. A non-secure
  /// [Random] here would make salts predictable and defeat their purpose.
  static Uint8List generateSalt() {
    final random = Random.secure();
    final salt = Uint8List(saltLength);
    for (var i = 0; i < saltLength; i++) {
      salt[i] = random.nextInt(256);
    }
    return salt;
  }

  /// Derives the encryption key and the verification value.
  ///
  /// Deterministic: the same [passphrase], [salt], and [parameters] always
  /// produce the same output, which is what makes restoring a vault on a
  /// new device possible.
  ///
  /// [parameters] is required rather than defaulted: which cost factors a
  /// vault was created with is security-critical and must be an explicit,
  /// visible decision at every call site — a silent default is exactly how
  /// a vault ends up re-derived under the wrong parameters.
  ///
  /// Neither the passphrase nor any derived byte is ever logged.
  Future<DerivedKeys> deriveKeys({
    required String passphrase,
    required Uint8List salt,
    required KdfParameters parameters,
  }) async {
    // Argon2id is the expensive part; keep it off the platform thread.
    final masterKey = await Isolate.run(
      () => _deriveMasterKey(
        passphrase: passphrase,
        salt: salt,
        parameters: parameters,
      ),
    );

    try {
      final encryptionKey = await _expand(
        masterKey: masterKey,
        info: _encryptionInfo,
        lengthBytes: parameters.keyLengthBytes,
      );
      final verifier = await _expand(
        masterKey: masterKey,
        info: _verificationInfo,
        lengthBytes: parameters.keyLengthBytes,
      );
      return DerivedKeys(encryptionKey: encryptionKey, verifier: verifier);
    } finally {
      // The master key itself is not needed beyond this point.
      masterKey.fillRange(0, masterKey.length, 0);
    }
  }

  /// HKDF-SHA256 expansion of [masterKey] under a domain-separating label.
  static Future<Uint8List> _expand({
    required Uint8List masterKey,
    required String info,
    required int lengthBytes,
  }) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: lengthBytes);
    // No HKDF salt is passed (the default is empty): the Argon2id output
    // is already uniformly random and salted, so a second salt would add
    // nothing. The `info` label is what separates the two outputs.
    final derived = await hkdf.deriveKey(
      secretKey: SecretKey(masterKey),
      info: info.codeUnits,
    );
    return Uint8List.fromList(await derived.extractBytes());
  }
}

/// Runs Argon2id. Top-level so it can be sent to a background isolate.
///
/// Returns the raw master key, which the caller expands with HKDF and then
/// zeroes.
Future<Uint8List> _deriveMasterKey({
  required String passphrase,
  required Uint8List salt,
  required KdfParameters parameters,
}) async {
  final algorithm = Argon2id(
    memory: parameters.memoryKib,
    iterations: parameters.iterations,
    parallelism: parameters.parallelism,
    hashLength: parameters.keyLengthBytes,
  );
  final key = await algorithm.deriveKey(
    // Argon2 calls the password the "secret key" and the salt the "nonce".
    secretKey: SecretKey(_utf8Bytes(passphrase)),
    nonce: salt,
  );
  return Uint8List.fromList(await key.extractBytes());
}

/// Encodes a passphrase as UTF-8.
///
/// Explicit rather than relying on `String.codeUnits`, which would emit
/// UTF-16 code units and silently derive a different key for any
/// passphrase containing non-ASCII characters (accents, emoji, non-Latin
/// scripts) depending on the caller.
Uint8List _utf8Bytes(String value) =>
    Uint8List.fromList(const Utf8Encoder().convert(value));

/// The key material produced by [KeyDerivation.deriveKeys].
///
/// Callers should [destroy] this once the keys have been stored or used.
class DerivedKeys {
  DerivedKeys({required this.encryptionKey, required this.verifier});

  /// AES-256-GCM key. Never persisted in plaintext, never logged.
  final Uint8List encryptionKey;

  /// Value compared against the stored verifier to check a passphrase.
  /// Safe to persist; reveals nothing about [encryptionKey].
  final Uint8List verifier;

  /// Overwrites both buffers with zeroes.
  ///
  /// Best-effort only. Dart offers no guarantee that the GC has not
  /// already copied these bytes elsewhere, and gives no way to pin or wipe
  /// memory. This meaningfully shortens the window in which key material
  /// sits in the heap; it is not a guarantee of erasure.
  void destroy() {
    encryptionKey.fillRange(0, encryptionKey.length, 0);
    verifier.fillRange(0, verifier.length, 0);
  }
}
