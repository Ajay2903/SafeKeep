import 'package:meta/meta.dart';

/// How far ahead of an expiry date the user wants to be warned.
///
/// Stored as a set of day offsets. Three by default — a month out to act
/// on, a fortnight out to chase, and a week out as a last call — because
/// a single reminder is easy to dismiss and forget, and more than three
/// trains people to ignore them.
@immutable
class ReminderSettings {
  const ReminderSettings({required this.offsetsInDays});

  /// Parses a value written by [encode]. Anything unparseable falls back
  /// to [defaults] — a corrupt preference should cost the user their
  /// customisation, never their reminders.
  factory ReminderSettings.decode(String? encoded) {
    if (encoded == null) return defaults;
    if (encoded.trim().isEmpty) {
      // Deliberately distinct from null: an empty string means the user
      // turned every reminder off, which must be honoured rather than
      // silently reset to the defaults.
      return const ReminderSettings(offsetsInDays: {});
    }

    final parsed = <int>{};
    for (final part in encoded.split(',')) {
      final value = int.tryParse(part.trim());
      if (value == null || value <= 0) return defaults;
      parsed.add(value);
    }
    return ReminderSettings(offsetsInDays: parsed);
  }

  /// The default schedule: 30, 14, and 7 days before expiry.
  static const ReminderSettings defaults = ReminderSettings(
    offsetsInDays: {30, 14, 7},
  );

  /// Offsets a user may choose from. Deliberately a fixed menu rather
  /// than free numeric entry: an arbitrary "271 days" serves nobody, and
  /// a picker of sensible intervals is faster to use than a text field.
  static const List<int> selectableOffsets = [90, 60, 30, 14, 7, 3, 1];

  /// Days before expiry at which to notify. A set, so the same offset
  /// cannot be scheduled twice.
  final Set<int> offsetsInDays;

  bool get isEmpty => offsetsInDays.isEmpty;

  /// Offsets in the order they will fire — furthest out first.
  List<int> get sortedDescending =>
      offsetsInDays.toList()..sort((a, b) => b.compareTo(a));

  ReminderSettings toggle(int offset) {
    final next = Set<int>.from(offsetsInDays);
    if (!next.remove(offset)) next.add(offset);
    return ReminderSettings(offsetsInDays: next);
  }

  /// Serialises to a comma-separated list, e.g. `30,14,7`.
  ///
  /// Plain text rather than JSON because the value is a list of small
  /// integers and nothing more; a JSON array would only add quoting to
  /// parse back out.
  String encode() => sortedDescending.join(',');

  @override
  bool operator ==(Object other) =>
      other is ReminderSettings &&
      other.offsetsInDays.length == offsetsInDays.length &&
      other.offsetsInDays.containsAll(offsetsInDays);

  @override
  int get hashCode => Object.hashAllUnordered(offsetsInDays);
}
