import 'package:flutter/material.dart';
import 'package:safekeep/core/constants/app_spacing.dart';

/// One row in a `SettingsSection`.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.isExternal = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  /// Whether tapping leaves the app for a browser.
  ///
  /// Shown with a different trailing icon so the user knows before they
  /// tap. In an app built on "nothing leaves this device", quietly
  /// handing someone to a browser would be a small betrayal of the
  /// premise even when the destination is harmless.
  final bool isExternal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      link: isExternal,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                isExternal ? Icons.open_in_new : Icons.chevron_right,
                size: isExternal ? 16 : 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
