import 'package:flutter/material.dart';
import 'package:safekeep/core/constants/app_shape.dart';
import 'package:safekeep/core/constants/app_spacing.dart';

/// A titled group of settings rows.
///
/// Grouping rather than one flat list: a settings screen that grows past
/// about five items becomes unscannable without headings, and this one is
/// expected to grow.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            bottom: AppSpacing.sm,
          ),
          child: Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AppShape.radiusLarge),
            border: Border.all(color: theme.colorScheme.outline),
          ),
          // Clipped so a row's ink ripple follows the container's
          // rounded corners instead of squaring them off.
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    indent: 56,
                    color: theme.colorScheme.outline,
                  ),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}
