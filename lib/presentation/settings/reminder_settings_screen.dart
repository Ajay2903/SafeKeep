import 'dart:async';

import 'package:flutter/material.dart';
import 'package:safekeep/core/constants/app_shape.dart';
import 'package:safekeep/core/constants/app_spacing.dart';
import 'package:safekeep/core/theme/app_colors.dart';
import 'package:safekeep/data/database/settings_dao.dart';
import 'package:safekeep/data/reminders/reminder_scheduler.dart';
import 'package:safekeep/domain/models/reminder_settings.dart';

/// Lets the user choose when to be reminded before a document expires.
///
/// Changing these affects documents saved *afterwards*. Rescheduling
/// every existing document would mean walking the whole vault on a
/// settings change, and is deferred rather than done silently — the
/// screen says so plainly rather than letting the user assume otherwise.
class ReminderSettingsScreen extends StatefulWidget {
  const ReminderSettingsScreen({
    required this.settingsDao,
    required this.reminders,
    super.key,
  });

  final SettingsDao settingsDao;
  final ReminderScheduler reminders;

  @override
  State<ReminderSettingsScreen> createState() => _ReminderSettingsScreenState();
}

class _ReminderSettingsScreenState extends State<ReminderSettingsScreen> {
  ReminderSettings _settings = ReminderSettings.defaults;
  bool _loading = true;
  bool _notificationsAllowed = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final settings = await widget.settingsDao.readReminderSettings();
    final allowed = await widget.reminders.hasPermission();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _notificationsAllowed = allowed;
      _loading = false;
    });
  }

  Future<void> _toggle(int offset) async {
    final next = _settings.toggle(offset);
    setState(() => _settings = next);
    await widget.settingsDao.writeReminderSettings(next);

    // Ask for permission the first time a reminder is actually wanted,
    // so the prompt arrives with a visible reason rather than at launch.
    if (next.isEmpty || _notificationsAllowed) return;
    final granted = await widget.reminders.requestPermission();
    if (mounted) setState(() => _notificationsAllowed = granted);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Text(
                  'When a document has an expiry date, remind me:',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Reminders are scheduled on this device only. They never '
                  'name the document — a notification says just that '
                  'something is expiring, so nothing is readable from a '
                  'locked screen.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.lg),
                for (final offset in ReminderSettings.selectableOffsets)
                  _OffsetTile(
                    offset: offset,
                    selected: _settings.offsetsInDays.contains(offset),
                    onChanged: (_) => _toggle(offset),
                  ),
                if (_settings.isEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  const _Notice(
                    icon: Icons.notifications_off_outlined,
                    message:
                        'No reminders will be scheduled. Expiry dates '
                        'are still shown in your vault.',
                  ),
                ],
                if (!_notificationsAllowed && !_settings.isEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  const _Notice(
                    icon: Icons.error_outline,
                    isWarning: true,
                    message:
                        'Notifications are turned off for this app, so '
                        'reminders will not appear. You can enable them in '
                        'your device settings.',
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                const _Notice(
                  icon: Icons.info_outline,
                  message:
                      'Changes apply to documents you save from now '
                      'on. Documents already saved keep the reminders they '
                      'were given.',
                ),
              ],
            ),
    );
  }
}

class _OffsetTile extends StatelessWidget {
  const _OffsetTile({
    required this.offset,
    required this.selected,
    required this.onChanged,
  });

  final int offset;
  final bool selected;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: selected,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(_label),
    );
  }

  String get _label => switch (offset) {
    1 => '1 day before',
    7 => '1 week before',
    14 => '2 weeks before',
    30 => '1 month before',
    60 => '2 months before',
    90 => '3 months before',
    _ => '$offset days before',
  };
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.message,
    this.isWarning = false,
  });

  final IconData icon;
  final String message;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isWarning
        ? AppColors.danger
        : theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isWarning
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppShape.radiusMedium),
        border: Border.all(
          color: isWarning ? AppColors.danger : theme.colorScheme.outline,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
