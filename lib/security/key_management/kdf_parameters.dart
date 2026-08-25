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
/// These were **tuned against a real low-end Android device**, not
/// extrapolated from desktop. An earlier 64 MiB / t=3 setting measured
/// ~295 ms on an M-series laptop but **6 s on the target phone** — past
/// the 5 s Android ANR ceiling and a bad first-run experience. The values
/// below halve that to roughly 3 s.
///
/// * **memory = 49 152 KiB (48 MiB).** The dominant security parameter.
///   Argon2id's resistance to GPU/ASIC cracking comes from memory
///   hardness, not raw passes: memory is what caps how many guesses an
///   attacker can run *in parallel* (an 8 GB GPU fits ~170 concurrent
///   instances at 48 MiB, but ~420 at 19 MiB). OWASP's floor is 19 MiB;
///   this is ~2.5x that. Going much higher also risks OOM on low-memory
///   Android devices.
/// * **iterations = 2.** OWASP's floor, and the knob that was cut to buy
///   the speed. Deliberate ordering: passes only add *serial* work, so at
///   any fixed time budget more memory with fewer passes beats less
///   memory with more. 48 MiB / t=2 and 32 MiB / t=3 cost the same ~3 s
///   here, but the former keeps half again as much memory hardness.
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
/// weak passphrase and the plaintext, which is why memory sits well above
/// the published floor even though iterations sit at it.
///
/// # What actually pays this cost
///
/// Worth knowing before tuning further: **only vault setup, passphrase
/// unlock, and passphrase verification run Argon2id.** Biometric unlock
/// reads the key straight from Keystore/Keychain and does no derivation
/// at all, so the everyday unlock is unaffected by these values. The cost
/// is paid once at setup and thereafter only when biometrics are
/// unavailable, fail, or the vault is opened on a new device.
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
    memoryKib: 49152,
    iterations: 2,
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
