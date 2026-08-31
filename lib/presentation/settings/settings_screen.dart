import 'package:flutter/material.dart';
import 'package:safekeep/core/constants/app_shape.dart';
import 'package:safekeep/core/constants/app_spacing.dart';
import 'package:safekeep/core/theme/app_colors.dart';
import 'package:safekeep/data/database/settings_dao.dart';
import 'package:safekeep/data/reminders/reminder_scheduler.dart';
import 'package:safekeep/presentation/settings/delete_all_data_screen.dart';
import 'package:safekeep/presentation/settings/reminder_settings_screen.dart';
import 'package:safekeep/presentation/settings/widgets/pro_upgrade_card.dart';
import 'package:safekeep/presentation/settings/widgets/settings_section.dart';
import 'package:safekeep/presentation/settings/widgets/settings_tile.dart';
import 'package:url_launcher/url_launcher.dart';

/// The app's settings.
///
/// Ordered by how often it is wanted and how consequential it is: the
/// upgrade offer first, everyday preferences next, legal and explanatory
/// material after that, and the irreversible action last and visually
/// separated. Nobody reaches "delete everything" by accident on their way
/// somewhere else.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.settingsDao,
    required this.reminders,
    super.key,
  });

  // TODO(phase9): replace with the real marketing and legal URLs once the
  // site exists. Placeholders so the plumbing is exercised, not real
  // destinations.
  static final Uri _termsUrl = Uri.parse('https://www.google.com');
  static final Uri _privacyUrl = Uri.parse('https://www.google.com');
  static final Uri _securityUrl = Uri.parse('https://www.google.com');

  final SettingsDao settingsDao;
  final ReminderScheduler reminders;

  Future<void> _open(BuildContext context, Uri url) async {
    // externalApplication, not an in-app web view: an embedded browser
    // inside a vault app invites the question of what it can see, and a
    // privacy policy is exactly the page a user may want to verify is
    // genuinely on the site it claims to be.
    final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open your browser.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          const ProUpgradeCard(),
          const SizedBox(height: AppSpacing.xl),

          SettingsSection(
            title: 'Preferences',
            children: [
              SettingsTile(
                icon: Icons.notifications_outlined,
                title: 'Reminders',
                subtitle: 'When to be warned before a document expires',
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => ReminderSettingsScreen(
                      settingsDao: settingsDao,
                      reminders: reminders,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          SettingsSection(
            title: 'About',
            children: [
              SettingsTile(
                icon: Icons.shield_outlined,
                title: 'How your data is protected',
                subtitle:
                    'Encryption, keys, and what never leaves this '
                    'device',
                isExternal: true,
                onTap: () => _open(context, _securityUrl),
              ),
              SettingsTile(
                icon: Icons.lock_outline,
                title: 'Privacy policy',
                isExternal: true,
                onTap: () => _open(context, _privacyUrl),
              ),
              SettingsTile(
                icon: Icons.description_outlined,
                title: 'Terms of service',
                isExternal: true,
                onTap: () => _open(context, _termsUrl),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),

          const _DangerZone(),
        ],
      ),
    );
  }
}

/// Destructive actions, deliberately set apart.
///
/// Its own visual treatment rather than another row in a list: a
/// permanently destructive action should not look like a preference, and
/// should not be reachable by the same absent-minded tap.
class _DangerZone extends StatelessWidget {
  const _DangerZone();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(AppShape.radiusLarge),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: AppColors.danger,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Delete all data',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: AppColors.danger,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Permanently erases every document, its encryption key, and '
            'all reminders from this device. There is no backup and no '
            'way to undo it.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: AppColors.danger),
            ),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => const DeleteAllDataScreen(),
              ),
            ),
            child: const Text('Delete all data'),
          ),
        ],
      ),
    );
  }
}
