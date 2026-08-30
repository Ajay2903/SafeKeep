import 'package:flutter_test/flutter_test.dart';
import 'package:safekeep/domain/models/reminder_settings.dart';

void main() {
  group('defaults', () {
    test('are 30, 14, and 7 days', () {
      expect(ReminderSettings.defaults.offsetsInDays, {30, 14, 7});
    });

    test('every default is offerable in the picker', () {
      for (final offset in ReminderSettings.defaults.offsetsInDays) {
        expect(ReminderSettings.selectableOffsets, contains(offset));
      }
    });
  });

  group('encoding', () {
    test('round-trips', () {
      const settings = ReminderSettings(offsetsInDays: {90, 7, 1});

      expect(ReminderSettings.decode(settings.encode()), settings);
    });

    test('writes furthest-out first', () {
      const settings = ReminderSettings(offsetsInDays: {7, 90, 30});

      expect(settings.encode(), '90,30,7');
    });

    test('an absent value falls back to the defaults', () {
      expect(ReminderSettings.decode(null), ReminderSettings.defaults);
    });

    test('an empty value means reminders off, not defaults', () {
      // These must stay distinguishable: a user who turned every reminder
      // off should not silently get them all back.
      expect(ReminderSettings.decode('').isEmpty, isTrue);
      expect(ReminderSettings.decode('   ').isEmpty, isTrue);
    });

    test('a corrupt value falls back to the defaults', () {
      // Losing a customisation is acceptable; losing reminders entirely
      // because of a bad byte is not.
      for (final corrupt in ['abc', '30,,7', '30,x', '-5', '0,30']) {
        expect(
          ReminderSettings.decode(corrupt),
          ReminderSettings.defaults,
          reason: 'must recover from "$corrupt"',
        );
      }
    });

    test('tolerates surrounding whitespace', () {
      expect(
        ReminderSettings.decode(' 30 , 7 '),
        const ReminderSettings(offsetsInDays: {30, 7}),
      );
    });
  });

  group('toggle', () {
    test('adds an absent offset', () {
      const settings = ReminderSettings(offsetsInDays: {30});

      expect(settings.toggle(7).offsetsInDays, {30, 7});
    });

    test('removes a present offset', () {
      const settings = ReminderSettings(offsetsInDays: {30, 7});

      expect(settings.toggle(7).offsetsInDays, {30});
    });

    test('can empty the set entirely', () {
      const settings = ReminderSettings(offsetsInDays: {30});

      expect(settings.toggle(30).isEmpty, isTrue);
    });

    test('does not mutate the original', () {
      const settings = ReminderSettings(offsetsInDays: {30});

      settings.toggle(7);

      expect(settings.offsetsInDays, {30});
    });
  });

  group('ordering', () {
    test('sortedDescending fires furthest-out first', () {
      const settings = ReminderSettings(offsetsInDays: {7, 90, 30});

      expect(settings.sortedDescending, [90, 30, 7]);
    });
  });

  group('equality', () {
    test('ignores insertion order', () {
      expect(
        const ReminderSettings(offsetsInDays: {30, 7}),
        const ReminderSettings(offsetsInDays: {7, 30}),
      );
    });

    test('differs on contents', () {
      expect(
        const ReminderSettings(offsetsInDays: {30}),
        isNot(const ReminderSettings(offsetsInDays: {7})),
      );
    });
  });
}
