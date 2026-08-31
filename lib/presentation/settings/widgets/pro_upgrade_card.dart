import 'package:flutter/material.dart';
import 'package:safekeep/core/constants/app_shape.dart';
import 'package:safekeep/core/constants/app_spacing.dart';
import 'package:safekeep/core/theme/app_colors.dart';

/// The upgrade offer, at the top of settings.
///
/// # Why it looks the way it does
///
/// The rest of the app is deliberately restrained — a vault should feel
/// like a safe, not a storefront. This is the one place that may raise
/// its voice, so it uses the accent as a gradient rather than a flat
/// fill, which reads as a distinct surface rather than a large button.
///
/// It stays inside the existing palette. A gold or purple "premium"
/// treatment would look bolted on from another product, and the point of
/// the card is that Pro is the same trustworthy app with more of it.
///
/// Benefits are stated as capabilities the user gains, not features the
/// product has: "Unlimited documents", not "No document cap".
// TODO(phase9): wire to a real paywall and purchase flow. The card, its
// copy, and its benefits are placeholders until the tiers are decided.
class ProUpgradeCard extends StatelessWidget {
  const ProUpgradeCard({super.key});

  static const List<({IconData icon, String label})> _benefits = [
    (icon: Icons.cloud_done_outlined, label: 'Unlimited Drive backup'),
    (icon: Icons.description_outlined, label: 'Unlimited documents'),
    (icon: Icons.shield_outlined, label: 'Higher encryption standard'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppShape.radiusXLarge),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.accent, AppColors.accentPressed],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showPlaceholder(context),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(
                          AppShape.radiusSmall,
                        ),
                      ),
                      child: Text(
                        'PRO',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Your whole life,\nkept safe.',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                for (final benefit in _benefits) ...[
                  _Benefit(icon: benefit.icon, label: benefit.label),
                  const SizedBox(height: AppSpacing.sm),
                ],
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.accentPressed,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: () => _showPlaceholder(context),
                    child: const Text('See what Pro includes'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPlaceholder(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Pro is not available yet.')),
      );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.9)),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white),
          ),
        ),
      ],
    );
  }
}
