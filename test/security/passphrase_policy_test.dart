import 'package:flutter_test/flutter_test.dart';
import 'package:safekeep/security/passphrase_policy.dart';

void main() {
  group('minimum length', () {
    test('anything shorter than 12 characters is rejected', () {
      for (final short in ['', 'a', 'hunter2', 'elevenchar']) {
        expect(
          PassphrasePolicy.assess(short).strength,
          PassphraseStrength.tooShort,
          reason: 'must reject "$short"',
        );
      }
    });

    test('tooShort is the only unacceptable strength', () {
      // A vault has no recovery path, so a short passphrase is blocked
      // outright rather than warned about.
      expect(PassphraseStrength.tooShort.isAcceptable, isFalse);
      for (final strength in PassphraseStrength.values) {
        if (strength != PassphraseStrength.tooShort) {
          expect(strength.isAcceptable, isTrue);
        }
      }
    });

    test('exactly 12 characters is accepted', () {
      expect(
        PassphrasePolicy.assess('abcdefghijkm').strength.isAcceptable,
        isTrue,
      );
    });
  });

  group('strength ordering', () {
    test('longer passphrases score at least as high', () {
      final short = PassphrasePolicy.assess('correct horse').estimatedBits;
      final long = PassphrasePolicy.assess(
        'correct horse battery staple',
      ).estimatedBits;

      expect(long, greaterThan(short));
    });

    test('more character classes score higher at equal length', () {
      final lower = PassphrasePolicy.assess('abcdkfmghjqx').estimatedBits;
      final mixed = PassphrasePolicy.assess('aBcDkF9!hjQx').estimatedBits;

      expect(mixed, greaterThan(lower));
    });

    test('a four-word passphrase reaches at least strong', () {
      // The behaviour we most want to encourage: memorable and long.
      final assessment = PassphrasePolicy.assess(
        'correct horse battery staple',
      );

      expect(
        assessment.strength.index,
        greaterThanOrEqualTo(PassphraseStrength.strong.index),
      );
    });
  });

  group('penalties', () {
    test('a repeated character scores far below its raw length', () {
      // Twelve characters long and completely predictable.
      final repeated = PassphrasePolicy.assess('aaaaaaaaaaaa');
      final varied = PassphrasePolicy.assess('kqmxvbztrwnp');

      expect(repeated.estimatedBits, lessThan(varied.estimatedBits / 2));
      expect(repeated.strength, PassphraseStrength.weak);
    });

    test('a straight run of characters is discounted', () {
      final sequential = PassphrasePolicy.assess('abcdefghijkl');
      final scattered = PassphrasePolicy.assess('kqmxvbztrwnp');

      expect(sequential.estimatedBits, lessThan(scattered.estimatedBits));
    });

    test('digit runs are discounted too', () {
      final sequential = PassphrasePolicy.assess('123456789012');
      final scattered = PassphrasePolicy.assess('918274659301');

      expect(sequential.estimatedBits, lessThan(scattered.estimatedBits));
    });
  });

  group('honesty about the estimate', () {
    test('estimated bits are never negative', () {
      for (final candidate in [
        'aaaaaaaaaaaaaaaaaaaaaaaa',
        'abcdefghijklmnopqrstuvwx',
        '111111111111',
      ]) {
        expect(
          PassphrasePolicy.assess(candidate).estimatedBits,
          greaterThanOrEqualTo(0),
        );
      }
    });

    test('a known-bad passphrase still passes, as documented', () {
      // This estimator has no dictionary, so a common pattern scores far
      // better than it deserves. The limitation is deliberate and
      // documented rather than hidden; this test exists so nobody
      // mistakes the meter for a guarantee.
      final assessment = PassphrasePolicy.assess('Password123!');

      expect(assessment.strength.isAcceptable, isTrue);
    });

    test('non-ASCII characters are counted, not ignored', () {
      final assessment = PassphrasePolicy.assess('pässwörd-日本語');

      expect(assessment.estimatedBits, greaterThan(0));
      expect(assessment.strength.isAcceptable, isTrue);
    });
  });
}
