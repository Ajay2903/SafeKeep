import 'package:flutter/material.dart';
import 'package:safekeep/core/constants/app_motion.dart';
import 'package:safekeep/core/constants/app_shape.dart';
import 'package:safekeep/core/constants/app_spacing.dart';
import 'package:safekeep/core/theme/app_colors.dart';
import 'package:safekeep/domain/models/document.dart';
import 'package:safekeep/presentation/vault/document_visuals.dart';

/// One row in the document list.
///
/// Shows only metadata — nothing here decrypts a document, so scrolling a
/// large vault costs nothing beyond drawing text.
class DocumentCard extends StatelessWidget {
  const DocumentCard({
    required this.document,
    required this.onTap,
    super.key,
  });

  final Document document;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expiring = document.isExpiredAt(DateTime.now());

    return Semantics(
      button: true,
      label: '${document.title}, ${document.category.label}',
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppShape.radiusLarge),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppShape.radiusLarge),
          child: AnimatedContainer(
            duration: AppMotion.micro,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppShape.radiusLarge),
              border: Border.all(color: theme.colorScheme.outline),
            ),
            child: Row(
              children: [
                _Thumbnail(document: document),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        document.title,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${document.category.label} · '
                        '${formatFileSize(document.plaintextSizeBytes)}',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (document.expiresAt != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        _ExpiryChip(
                          expiresAt: document.expiresAt!,
                          expired: expiring,
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.document});

  final Document document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppShape.radiusMedium),
      ),
      // An icon rather than a rendered preview: a thumbnail would mean
      // decrypting every document just to draw the list, and would put
      // document contents on screen where a shoulder-surfer sees them
      // without the user opening anything.
      child: Icon(
        document.category.icon,
        size: 20,
        color: AppColors.accent,
      ),
    );
  }
}

class _ExpiryChip extends StatelessWidget {
  const _ExpiryChip({required this.expiresAt, required this.expired});

  final DateTime expiresAt;
  final bool expired;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = expired
        ? AppColors.danger
        : theme.colorScheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          expired ? Icons.error_outline : Icons.event_outlined,
          size: 13,
          color: color,
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          expired
              ? 'Expired ${formatDate(expiresAt)}'
              : 'Expires ${formatDate(expiresAt)}',
          style: theme.textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}
