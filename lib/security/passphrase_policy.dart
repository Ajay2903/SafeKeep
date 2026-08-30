import 'dart:math';

/// How strong a candidate passphrase looks.
enum PassphraseStrength {
  /// Below the minimum length. Setup is blocked.
  tooShort,
  weak,
  fair,
  strong,
  excellent;

  /// Whether a vault may be created with a passphrase of this strength.
  bool get isAcceptable => this != PassphraseStrength.tooShort;
}

/// The result of assessing a passphrase.
class PassphraseAssessment {
  const PassphraseAssessment({
    required this.strength,
    required this.estimatedBits,
  });

  final PassphraseStrength strength;

  /// Rough estimate of entropy in bits. See [PassphrasePolicy] for what
  /// this number is and is not.
  final double estimatedBits;
}

/// Minimum requirements and strength estimation for vault passphrases.
///
/// # Why this exists at all
///
/// The passphrase is the only barrier. There is no server to rate-limit
/// guesses, no account to lock out, and no recovery path. An attacker who
/// obtains the encrypted blobs guesses offline, in parallel, forever. The
/// Argon2id cost multiplies the price of each guess, but it cannot rescue
/// a passphrase that falls in the first million attempts.
///
/// # What the estimate is, and what it is not
///
/// [PassphrasePolicy.assess] computes a *ceiling*: length multiplied by
/// the bits per character implied by the character classes present, minus
/// crude penalties for repetition and sequences.
///
/// It does **not** know about dictionaries, leaked-password lists,
/// keyboard patterns, dates, or names. `Password1!` scores far better
/// here than it deserves in reality. A proper estimator (zxcvbn and
/// similar) carries a dictionary of tens of thousands of entries, which
/// is a meaningful dependency and app-size cost.
///
/// So this is deliberately framed as a floor that catches the obviously
/// hopeless, not a guarantee that anything passing it is safe — and the
/// UI is written to match, encouraging length rather than congratulating
/// the user on beating a meter.
// TODO(phase10): consider a bundled dictionary check before launch, so
// that leaked and common passphrases are rejected rather than merely
// scored. Weigh against app size, and keep it offline.
abstract final class PassphrasePolicy {
  /// Shortest passphrase a vault may be created with.
  ///
  /// Twelve characters is the usual modern floor, and matters more here
  /// than in a rate-limited system. It is a hard block rather than a
  /// warning: for a vault with no recovery path, letting someone choose
  /// six characters is not a choice worth respecting.
  static const int minimumLength = 12;

  /// Length at which the UI stops nudging for more.
  static const int comfortableLength = 20;

  static PassphraseAssessment assess(String passphrase) {
    if (passphrase.length < minimumLength) {
      return const PassphraseAssessment(
        strength: PassphraseStrength.tooShort,
        estimatedBits: 0,
      );
    }

    final bits = _estimateBits(passphrase);
    return PassphraseAssessment(
      strength: _classify(bits),
      estimatedBits: bits,
    );
  }

  static PassphraseStrength _classify(double bits) {
    // Thresholds are judgement calls, chosen so that a four-word
    // passphrase lands at "strong" rather than being talked down, since
    // memorable length is what we actually want to encourage.
    if (bits < 45) return PassphraseStrength.weak;
    if (bits < 65) return PassphraseStrength.fair;
    if (bits < 90) return PassphraseStrength.strong;
    return PassphraseStrength.excellent;
  }

  static double _estimateBits(String passphrase) {
    final codeUnits = passphrase.runes.toList();

    var hasLower = false;
    var hasUpper = false;
    var hasDigit = false;
    var hasSymbol = false;
    for (final rune in codeUnits) {
      if (rune >= 0x61 && rune <= 0x7A) {
        hasLower = true;
      } else if (rune >= 0x41 && rune <= 0x5A) {
        hasUpper = true;
      } else if (rune >= 0x30 && rune <= 0x39) {
        hasDigit = true;
      } else {
        hasSymbol = true;
      }
    }

    var alphabet = 0;
    if (hasLower) alphabet += 26;
    if (hasUpper) alphabet += 26;
    if (hasDigit) alphabet += 10;
    // Symbols and any non-ASCII are lumped together conservatively.
    if (hasSymbol) alphabet += 33;
    if (alphabet == 0) return 0;

    final rawBits = codeUnits.length * (log(alphabet) / log(2));

    // Distinct characters relative to length: "aaaaaaaaaaaa" has the
    // length of a decent passphrase and none of the unpredictability.
    final distinct = codeUnits.toSet().length;
    final variety = distinct / codeUnits.length;

    // Runs of consecutive code points ("abcdef", "123456") are cheap for
    // an attacker and should not be paid for at full rate.
    var sequential = 0;
    for (var i = 1; i < codeUnits.length; i++) {
      if ((codeUnits[i] - codeUnits[i - 1]).abs() == 1) sequential++;
    }
    final sequencePenalty = sequential / codeUnits.length;

    final adjusted = rawBits * variety * (1 - 0.5 * sequencePenalty);
    return adjusted < 0 ? 0 : adjusted;
  }
}
