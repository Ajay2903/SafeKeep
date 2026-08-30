import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:safekeep/core/constants/app_motion.dart';
import 'package:safekeep/core/constants/app_shape.dart';
import 'package:safekeep/core/constants/app_spacing.dart';
import 'package:safekeep/core/theme/app_colors.dart';
import 'package:safekeep/data/data_exceptions.dart';
import 'package:safekeep/domain/models/document.dart';
import 'package:safekeep/domain/repositories/document_repository.dart';
import 'package:safekeep/presentation/app/vault_session_cubit.dart';
import 'package:safekeep/presentation/app/vault_session_state.dart';
import 'package:safekeep/presentation/vault/document_form_screen.dart';
import 'package:safekeep/presentation/vault/document_visuals.dart';
import 'package:safekeep/security/security_exceptions.dart';

/// Shows one document: its metadata, and its decrypted contents.
///
/// # Where the plaintext lives
///
/// Decrypted bytes exist only in this widget's state, for as long as the
/// screen is on the tree. They are never written to a file, never handed
/// to a share sheet, and never cached. Leaving the screen drops the
/// reference; locking the vault removes the whole subtree, which does the
/// same thing more forcefully.
///
/// The bytes are deliberately *not* held in the cubit or any longer-lived
/// object — putting them there would keep a decrypted document alive
/// across navigation, which is precisely what an auto-lock is meant to
/// prevent.
class DocumentDetailScreen extends StatefulWidget {
  const DocumentDetailScreen({
    required this.document,
    required this.repository,
    super.key,
  });

  final Document document;
  final DocumentRepository repository;

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> {
  late Document _document = widget.document;
  Uint8List? _bytes;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_decrypt());
  }

  @override
  void dispose() {
    // Best-effort: overwrite the plaintext before dropping it. Dart
    // cannot guarantee the GC has not copied it already, but this closes
    // the obvious window rather than leaving it open.
    _bytes?.fillRange(0, _bytes!.length, 0);
    _bytes = null;
    super.dispose();
  }

  Future<void> _decrypt() async {
    try {
      final bytes = await widget.repository.openDocument(_document.id);
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    } on DecryptionAuthenticationException {
      _fail(
        'This document failed its integrity check. It has been modified '
        'or corrupted since it was saved, so it cannot be shown.',
      );
    } on DocumentBlobMissingException {
      _fail('The encrypted file for this document is missing.');
    } on VaultLockedException {
      // The vault locked while decrypting. The gate is already replacing
      // this screen; showing an error would flash on the way out.
      if (mounted) setState(() => _loading = false);
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _loading = false;
    });
  }

  Future<void> _edit() async {
    final result = await Navigator.of(context).push<DocumentFormResult>(
      MaterialPageRoute(
        builder: (_) => DocumentFormScreen(
          title: 'Edit details',
          submitLabel: 'Save changes',
          initial: _document,
        ),
      ),
    );
    if (result == null || !mounted) return;

    final updated = await widget.repository.updateDocument(
      _document.copyWith(
        title: result.title,
        category: result.category,
        tags: result.tags,
        notes: result.notes,
        expiresAt: result.expiresAt,
        clearNotes: result.notes == null,
        clearExpiresAt: result.expiresAt == null,
      ),
    );
    if (mounted) setState(() => _document = updated);
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this document?'),
        content: const Text(
          'The encrypted file and its details are removed from this '
          'device permanently. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      if (!mounted) return;
      Navigator.of(context).pop(_DetailResult.deleted);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Leave immediately if the vault locks while this screen is open.
    // The gate would remove the subtree anyway; popping first avoids a
    // frame where a decrypted document is still painted underneath.
    return BlocListener<VaultSessionCubit, VaultSessionState>(
      listener: (context, state) {
        if (state is! VaultUnlocked && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_document.title, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit details',
              onPressed: _edit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete document',
              onPressed: _confirmDelete,
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(child: _buildViewer()),
            _MetadataPanel(document: _document),
          ],
        ),
      ),
    );
  }

  Widget _buildViewer() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ViewerMessage(
        icon: Icons.gpp_bad_outlined,
        message: _error!,
        isError: true,
      );
    }

    final bytes = _bytes;
    if (bytes == null) return const SizedBox.shrink();

    if (_document.isImage) {
      return InteractiveViewer(
        maxScale: 6,
        child: Center(
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (context, _, _) => const _ViewerMessage(
              icon: Icons.broken_image_outlined,
              message:
                  'This image could not be displayed. The file may '
                  'not be in a supported format.',
              isError: true,
            ),
          ),
        ),
      );
    }

    if (_document.isPdf) {
      // PdfViewer.data keeps the bytes in memory — it does not stage them
      // through a temporary file, which would put a decrypted document on
      // disk and defeat the entire storage design.
      return PdfViewer.data(
        bytes,
        sourceName: _document.id,
        params: PdfViewerParams(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          errorBannerBuilder: (context, error, stackTrace, documentRef) =>
              const _ViewerMessage(
                icon: Icons.picture_as_pdf_outlined,
                message: 'This PDF could not be rendered.',
                isError: true,
              ),
        ),
      );
    }

    return const _ViewerMessage(
      icon: Icons.description_outlined,
      message:
          'This file type cannot be previewed. It is stored and '
          'encrypted, and can still be exported.',
      isError: false,
    );
  }
}

/// What the detail screen reports back to the list.
enum _DetailResult { deleted }

/// Value the list checks for after the detail screen pops.
const Object documentDeletedResult = _DetailResult.deleted;

class _ViewerMessage extends StatelessWidget {
  const _ViewerMessage({
    required this.icon,
    required this.message,
    required this.isError,
  });

  final IconData icon;
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isError
        ? AppColors.danger
        : theme.colorScheme.onSurfaceVariant;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetadataPanel extends StatelessWidget {
  const _MetadataPanel({required this.document});

  final Document document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expired = document.isExpiredAt(DateTime.now());

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.outline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    document.category.icon,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '${document.category.label} · '
                    '${formatFileSize(document.plaintextSizeBytes)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              if (document.expiresAt != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  expired
                      ? 'Expired ${formatDate(document.expiresAt!)}'
                      : 'Expires ${formatDate(document.expiresAt!)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: expired ? AppColors.danger : null,
                  ),
                ),
              ],
              if (document.tags.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final tag in document.tags)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(
                            AppShape.radiusSmall,
                          ),
                        ),
                        child: Text(
                          tag,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              if (document.notes != null) ...[
                const SizedBox(height: AppSpacing.md),
                AnimatedSize(
                  duration: AppMotion.short,
                  child: Text(
                    document.notes!,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
