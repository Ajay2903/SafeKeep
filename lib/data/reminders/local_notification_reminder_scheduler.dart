import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:safekeep/core/logging/app_logger.dart';
import 'package:safekeep/data/reminders/reminder_scheduler.dart';
import 'package:safekeep/domain/models/reminder_settings.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// [ReminderScheduler] backed by `flutter_local_notifications`.
// NOTE: needs on-device verification. Notification delivery, permission
// prompts, and OS battery optimisations cannot be exercised under
// flutter test.
class LocalNotificationReminderScheduler implements ReminderScheduler {
  LocalNotificationReminderScheduler({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const String _channelId = 'safekeep_expiry_reminders';
  static const String _channelName = 'Document expiry reminders';
  static const String _channelDescription =
      'Reminds you before a document in your vault expires.';

  /// The hour reminders fire, in the device's local time.
  ///
  /// Morning, so a reminder lands at a point in the day when acting on it
  /// is still possible — a renewal notice at 11pm gets dismissed and
  /// forgotten.
  static const int _hourOfDay = 9;

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialised = false;

  Future<void> _ensureInitialised() async {
    if (_initialised) return;

    tz_data.initializeTimeZones();

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // Permission is requested explicitly later, at the point a
          // reminder is actually wanted, rather than on first launch
          // where the prompt would arrive with no context.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _initialised = true;
  }

  @override
  Future<bool> hasPermission() async {
    await _ensureInitialised();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.areNotificationsEnabled() ?? false;
    }
    // iOS offers no read-only check without prompting, so treat an
    // unknown state as "ask" rather than claiming permission we may not
    // have.
    return false;
  }

  @override
  Future<bool> requestPermission() async {
    await _ensureInitialised();

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }

    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, badge: true) ?? false;
    }
    return false;
  }

  @override
  Future<void> scheduleFor({
    required String documentId,
    required DateTime expiresAt,
    required ReminderSettings settings,
  }) async {
    await _ensureInitialised();
    await cancelFor(documentId);
    if (settings.isEmpty) return;

    final now = DateTime.now();

    for (final offset in settings.sortedDescending) {
      final local = expiresAt.toLocal();
      final fireAt = DateTime(
        local.year,
        local.month,
        local.day,
        _hourOfDay,
      ).subtract(Duration(days: offset));

      // A reminder for a moment already past would either fire instantly
      // or be dropped, depending on the platform. Neither helps.
      if (!fireAt.isAfter(now)) continue;

      await _plugin.zonedSchedule(
        id: _notificationId(documentId, offset),
        // Converting the instant rather than relying on tz.local, which
        // defaults to UTC without a device-timezone plugin. TZDateTime.from
        // preserves the moment, so the notification fires at the right
        // real-world time regardless of which zone the database thinks is
        // local.
        scheduledDate: tz.TZDateTime.from(fireAt, tz.UTC),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        // Inexact deliberately. Exact alarms need SCHEDULE_EXACT_ALARM,
        // which Android increasingly restricts and which users can
        // revoke — and a reminder weeks ahead of an expiry does not need
        // minute precision. Avoiding the permission entirely is the
        // better trade.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: 'Document expiring',
        // Generic on purpose. This is read from a locked screen by
        // whoever is holding the phone.
        body: offset == 1
            ? 'A document in your vault expires tomorrow.'
            : 'A document in your vault expires in $offset days.',
      );
    }

    AppLogger.instance.info('Reminders scheduled for $documentId');
  }

  @override
  Future<void> cancelFor(String documentId) async {
    await _ensureInitialised();
    // Cancel across every selectable offset, not just the currently
    // configured ones: the user may have changed their settings since
    // these were scheduled, and a reminder whose offset is no longer
    // selected would otherwise be orphaned and fire anyway.
    for (final offset in ReminderSettings.selectableOffsets) {
      await _plugin.cancel(id: _notificationId(documentId, offset));
    }
  }

  @override
  Future<void> cancelAll() async {
    await _ensureInitialised();
    await _plugin.cancelAll();
    AppLogger.instance.info('All reminders cancelled');
  }

  /// Derives a stable 31-bit notification id from a document and offset.
  ///
  /// Stable so that rescheduling replaces a reminder rather than stacking
  /// duplicates, and so cancellation can find it without storing a map of
  /// ids anywhere. Masked to 31 bits because platform notification ids
  /// are signed 32-bit integers.
  static int _notificationId(String documentId, int offset) {
    return Object.hash(documentId, offset) & 0x7FFFFFFF;
  }
}
