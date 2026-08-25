import 'dart:convert';

import 'package:meta/meta.dart';

/// Argon2id cost parameters.
///
/// # Why these are persisted with the vault
///
/// These values are stored alongside the salt, **not** hardcoded at the
/// point of derivation. That is not incidental: Argon2id is only
/// deterministic for a fixed set of parameters, so if a future release
/// raised the cost factors and derivation always used the new values, every
/// existing vault would derive a different key and its documents would
/// become permanently undecryptable. Reading the parameters back from
/// storage means old vaults keep deriving with the parameters they were
/// created under, while new vaults get the stronger defaults.
///
/// # Chosen defaults ([current]) and the reasoning
///
/// * **memory = 65 536 KiB (64 MiB).** The dominant security parameter.
///   Argon2id's resistance to GPU/ASIC cracking comes from memory
///   hardness, not raw passes, so memory is where budget is best spent.
///   OWASP's floor is 19 MiB; 64 MiB is ~3.4x that. Measured at ~295 ms
///   AOT on an M-series laptop, so roughly 1-3 s on a low-end phone —
///   acceptable as a once-per-unlock cost. Going higher (128 MiB measured
///   at ~604 ms) risks OOM on low-memory Android devices for a
///   proportionally smaller security gain.
/// * **iterations = 3.** OWASP's floor is 2. Passes are the cheap knob
///   once memory is set; 3 adds margin at ~1/3 more time.
/// * **parallelism = 1.** Argon2's `p` models *the attacker's* per-guess
///   parallelism, so raising it does not help the defender. OWASP
///   recommends 1. It also keeps derivation single-threaded and therefore
///   perfectly reproducible across devices.
/// * **keyLength = 32 bytes.** 256 bits, matching AES-256. More output
///   than the cipher consumes would be wasted.
///
/// # Threat model note
///
/// SafeKeep is zero-knowledge with no server, so there is no rate limiting
/// anywhere. An attacker who obtains encrypted blobs (e.g. from the user's
/// own cloud backup) can guess passphrases offline, unlimited and in
/// parallel. The KDF cost is therefore the *only* thing standing between a
/// weak passphrase and the plaintext, which is why these are set well
/// above the published minimums rather than at them.
@immutable
class KdfParameters {
  const KdfParameters({
    required this.memoryKib,
    required this.iterations,
    required this.parallelism,
    required this.keyLengthBytes,
  });

  /// Restores parameters previously written by [toJson].
  ///
  /// Throws [FormatException] on anything malformed — a vault whose
  /// parameters cannot be read must fail loudly rather than silently fall
  /// back to defaults, which would derive the wrong key.
  factory KdfParameters.fromJson(String json) {
    final Object? decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('KDF parameters are not a JSON object.');
    }
    final memoryKib = decoded['memoryKib'];
    final iterations = decoded['iterations'];
    final parallelism = decoded['parallelism'];
    final keyLengthBytes = decoded['keyLengthBytes'];
    if (memoryKib is! int ||
        iterations is! int ||
        parallelism is! int ||
        keyLengthBytes is! int) {
      throw const FormatException(
        'KDF parameters are missing a required integer field.',
      );
    }
    return KdfParameters(
      memoryKib: memoryKib,
      iterations: iterations,
      parallelism: parallelism,
      keyLengthBytes: keyLengthBytes,
    );
  }

  /// Defaults for vaults created by this build. See the class doc for the
  /// reasoning behind each value.
  static const KdfParameters current = KdfParameters(
    memoryKib: 65536,
    iterations: 3,
    parallelism: 1,
    keyLengthBytes: 32,
  );

  /// Memory cost, in 1 KiB blocks.
  final int memoryKib;

  /// Number of passes over memory.
  final int iterations;

  /// Argon2 `p`. Models attacker parallelism; kept at 1.
  final int parallelism;

  /// Length of the derived master key, in bytes.
  final int keyLengthBytes;

  String toJson() => jsonEncode({
    'memoryKib': memoryKib,
    'iterations': iterations,
    'parallelism': parallelism,
    'keyLengthBytes': keyLengthBytes,
  });

  @override
  bool operator ==(Object other) =>
      other is KdfParameters &&
      other.memoryKib == memoryKib &&
      other.iterations == iterations &&
      other.parallelism == parallelism &&
      other.keyLengthBytes == keyLengthBytes;

  @override
  int get hashCode =>
      Object.hash(memoryKib, iterations, parallelism, keyLengthBytes);
}
