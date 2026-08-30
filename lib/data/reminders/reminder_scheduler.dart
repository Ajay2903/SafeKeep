import 'package:safekeep/domain/models/reminder_settings.dart';

/// Schedules on-device reminders ahead of a document's expiry.
///
/// # What a reminder may say
///
/// Notifications appear on a locked screen, where anyone holding the
/// phone can read them. So the text is deliberately generic — "A
/// document expires in 30 days" — and never carries a title, category,
/// tag, or any other detail. A notification reading "Passport expires in
/// 7 days" would leak, to a glance, exactly what the vault exists to
/// keep private.
///
/// Nothing identifying goes in the payload either. Tapping a reminder
/// opens the app, which then requires an unlock like any other launch.
///
/// # Entirely on-device
///
/// These are local notifications scheduled by the OS. No server is
/// involved and no expiry date leaves the device.
abstract interface class ReminderScheduler {
  /// Whether the platform will currently deliver notifications.
  Future<bool> hasPermission();

  /// Asks for notification permission, returning whether it was granted.
  ///
  /// Called at the point a reminder is first actually wanted rather than
  /// at launch, so the prompt arrives with a reason the user can see.
  Future<bool> requestPermission();

  /// Replaces any reminders for [documentId] with ones derived from
  /// [expiresAt] and [settings].
  ///
  /// Existing reminders for the document are cancelled first, so an
  /// edited expiry date never leaves stale notifications scheduled.
  /// Offsets already in the past are skipped — scheduling a reminder for
  /// last Tuesday would either fire immediately or not at all, depending
  /// on the platform, and neither is useful.
  Future<void> scheduleFor({
    required String documentId,
    required DateTime expiresAt,
    required ReminderSettings settings,
  });

  /// Cancels every reminder for one document. Safe when none exist.
  Future<void> cancelFor(String documentId);

  /// Cancels every reminder the app has scheduled.
  ///
  /// Used when the vault is deleted: the documents are gone, so a
  /// notification about one expiring would be both useless and a small
  /// disclosure that a vault once existed.
  Future<void> cancelAll();
}

/// A scheduler that does nothing.
///
/// The default in `VaultDocumentRepository` so tests and any future
/// headless use construct without a platform channel. Unlike a silent
/// default for, say, KDF parameters — where a wrong value corrupts data
/// irrecoverably — the worst this can do is omit an optional
/// convenience, which is visible and harmless.
class NoopReminderScheduler implements ReminderScheduler {
  const NoopReminderScheduler();

  @override
  Future<bool> hasPermission() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> scheduleFor({
    required String documentId,
    required DateTime expiresAt,
    required ReminderSettings settings,
  }) async {}

  @override
  Future<void> cancelFor(String documentId) async {}

  @override
  Future<void> cancelAll() async {}
}
