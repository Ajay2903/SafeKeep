import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:safekeep/core/constants/app_motion.dart';
import 'package:safekeep/core/constants/app_shape.dart';
import 'package:safekeep/core/constants/app_spacing.dart';
import 'package:safekeep/core/theme/app_colors.dart';
import 'package:safekeep/data/mime_types.dart';
import 'package:safekeep/data/scanning/document_scanner.dart';
import 'package:safekeep/domain/models/document.dart';
import 'package:safekeep/domain/repositories/document_repository.dart';
import 'package:safekeep/presentation/app/vault_session_cubit.dart';
import 'package:safekeep/presentation/vault/document_detail_screen.dart';
import 'package:safekeep/presentation/vault/document_form_screen.dart';
import 'package:safekeep/presentation/vault/document_list_cubit.dart';
import 'package:safekeep/presentation/vault/document_list_state.dart';
import 'package:safekeep/presentation/vault/document_visuals.dart';
import 'package:safekeep/presentation/vault/widgets/document_card.dart';
import 'package:safekeep/presentation/widgets/fade_slide_in.dart';
import 'package:safekeep/presentation/widgets/vault_mark.dart';

/// The vault's main surface: search, filter, and the document list.
class VaultHomeScreen extends StatelessWidget {
  const VaultHomeScreen({
    required this.repository,
    required this.scanner,
    super.key,
  });

  final DocumentRepository repository;
  final DocumentScanner scanner;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) {
        final cubit = DocumentListCubit(repository: repository);
        unawaited(cubit.load());
        return cubit;
      },
      child: _VaultHomeView(repository: repository, scanner: scanner),
    );
  }
}

class _VaultHomeView extends StatefulWidget {
  const _VaultHomeView({required this.repository, required this.scanner});

  final DocumentRepository repository;
  final DocumentScanner scanner;

  @override
  State<_VaultHomeView> createState() => _VaultHomeViewState();
}

class _VaultHomeViewState extends State<_VaultHomeView> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Offers the two ways bytes can enter the vault.
  Future<void> _addDocument() async {
    final source = await showModalBottomSheet<_AddSource>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _AddSourceSheet(),
    );
    if (source == null || !mounted) return;

    switch (source) {
      case _AddSource.scan:
        await _scan();
      case _AddSource.import:
        await _import();
    }
  }

  /// Scan with the camera. The scanner is just another source of bytes:
  /// from here on the path is identical to importing a file.
  Future<void> _scan() async {
    final ScannedDocument? scan;
    try {
      scan = await widget.scanner.scan();
    } on DocumentScanException catch (error) {
      if (mounted) {
        _showMessage(
          error.isPermissionDenied
              ? 'Camera access is needed to scan. You can enable it in '
                    'Settings.'
              : 'The scan could not be completed.',
        );
      }
      return;
    }
    // Null means the user backed out of the scanner, which is normal.
    if (scan == null || !mounted) return;

    await _saveBytes(
      bytes: scan.bytes,
      mimeType: scan.mimeType,
      suggestedTitle: '',
      summary: scan.pageCount == 1
          ? 'Scanned document · ${formatFileSize(scan.bytes.length)}'
          : '${scan.pageCount} scanned pages · '
                '${formatFileSize(scan.bytes.length)}',
    );
  }

  /// Import an existing PDF or photo from the device.
  Future<void> _import() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: MimeTypes.pickableExtensions,
    );
    if (file == null || !mounted) return;

    // Read the bytes here and hand them straight to the vault. The
    // source file is the user's own and is left untouched; nothing is
    // copied to disk in the clear on our side.
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on Exception {
      if (mounted) _showMessage('That file could not be read.');
      return;
    }
    if (!mounted) return;

    await _saveBytes(
      bytes: bytes,
      mimeType: MimeTypes.forFileName(file.name),
      suggestedTitle: MimeTypes.titleFromFileName(file.name),
      summary: '${file.name} · ${formatFileSize(bytes.length)}',
    );
  }

  /// The single encrypt-and-store path both sources feed into.
  ///
  /// Kept in one place so scanning and importing cannot diverge — a
  /// document is a document once it is bytes, however it was captured.
  Future<void> _saveBytes({
    required Uint8List bytes,
    required String mimeType,
    required String suggestedTitle,
    required String summary,
  }) async {
    final result = await Navigator.of(context).push<DocumentFormResult>(
      MaterialPageRoute(
        builder: (_) => DocumentFormScreen(
          title: 'Add document',
          submitLabel: 'Encrypt and save',
          fileSummary: summary,
          suggestedTitle: suggestedTitle,
        ),
      ),
    );
    if (result == null || !mounted) return;

    try {
      await widget.repository.addDocument(
        bytes: bytes,
        title: result.title,
        category: result.category,
        mimeType: mimeType,
        tags: result.tags,
        notes: result.notes,
        expiresAt: result.expiresAt,
      );
      if (!mounted) return;
      await context.read<DocumentListCubit>().refresh();
      if (mounted) _showMessage('Document encrypted and saved.');
    } on Exception {
      if (mounted) _showMessage('That document could not be saved.');
    }
  }

  Future<void> _open(Document document) async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => DocumentDetailScreen(
          document: document,
          repository: widget.repository,
        ),
      ),
    );
    if (!mounted) return;

    if (result == documentDeletedResult) {
      await context.read<DocumentListCubit>().deleteDocument(document.id);
      if (mounted) _showMessage('Document deleted.');
      return;
    }
    // Metadata may have been edited on the detail screen.
    await context.read<DocumentListCubit>().refresh();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vault'),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: 'Lock vault',
            onPressed: () => context.read<VaultSessionCubit>().lock(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => unawaited(_addDocument()),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: BlocBuilder<DocumentListCubit, DocumentListState>(
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.isVaultEmpty) {
            return _EmptyVault(onImport: () => unawaited(_addDocument()));
          }

          return Column(
            children: [
              _SearchBar(
                controller: _searchController,
                onChanged: context.read<DocumentListCubit>().search,
                onClear: () {
                  _searchController.clear();
                  context.read<DocumentListCubit>().clearSearch();
                },
              ),
              _CategoryFilterBar(state: state),
              Expanded(
                child: _DocumentList(state: state, onOpen: _open),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Where a document's bytes come from.
enum _AddSource { scan, import }

class _AddSourceSheet extends StatelessWidget {
  const _AddSourceSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Scrollable rather than a bare Column: the sheet's natural height
    // exceeds a short screen in landscape or with large text sizes, and
    // a Column would simply overflow rather than letting the user reach
    // the second option.
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add a document', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.lg),
            _AddSourceTile(
              icon: Icons.document_scanner_outlined,
              title: 'Scan with camera',
              subtitle:
                  'Edges detected and cropped automatically. '
                  'Multiple pages become one PDF.',
              onTap: () => Navigator.of(context).pop(_AddSource.scan),
            ),
            const SizedBox(height: AppSpacing.sm),
            _AddSourceTile(
              icon: Icons.folder_open_outlined,
              title: 'Import a file',
              subtitle: 'Choose a PDF or photo already on this device.',
              onTap: () => Navigator.of(context).pop(_AddSource.import),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Either way, it is encrypted before it is stored.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AddSourceTile extends StatelessWidget {
  const _AddSourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(AppShape.radiusLarge),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppShape.radiusLarge),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppShape.radiusLarge),
            border: Border.all(color: theme.colorScheme.outline),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppShape.radiusMedium),
                ),
                child: Icon(icon, size: 20, color: AppColors.accent),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search titles and tags',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onClear,
                  tooltip: 'Clear search',
                ),
        ),
      ),
    );
  }
}

class _CategoryFilterBar extends StatelessWidget {
  const _CategoryFilterBar({required this.state});

  final DocumentListState state;

  @override
  Widget build(BuildContext context) {
    // Only categories that actually hold documents, so the bar never
    // offers a filter that can only produce an empty list.
    final categories = state.populatedCategories.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    if (categories.length < 2) return const SizedBox.shrink();

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final category = categories[index];
          return FilterChip(
            selected: state.category == category,
            onSelected: (_) =>
                context.read<DocumentListCubit>().filterByCategory(category),
            avatar: Icon(category.icon, size: 16),
            label: Text(category.label),
          );
        },
      ),
    );
  }
}

class _DocumentList extends StatelessWidget {
  const _DocumentList({required this.state, required this.onOpen});

  final DocumentListState state;
  final ValueChanged<Document> onOpen;

  @override
  Widget build(BuildContext context) {
    final documents = state.visible;

    if (documents.isEmpty) {
      return _NoResults(
        onClear: () => context.read<DocumentListCubit>()
          ..clearSearch()
          ..filterByCategory(null),
      );
    }

    return AnimatedSwitcher(
      duration: AppMotion.short,
      child: ListView.separated(
        key: ValueKey('${state.query}|${state.category}'),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          // Clears the floating action button.
          96,
        ),
        itemCount: documents.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          return FadeSlideIn(
            // Stagger only the first handful; beyond that the delay
            // would be longer than anyone waits before scrolling.
            delay: Duration(milliseconds: index < 8 ? index * 40 : 0),
            child: DocumentCard(
              document: documents[index],
              onTap: () => onOpen(documents[index]),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyVault extends StatelessWidget {
  const _EmptyVault({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const FadeSlideIn(child: VaultMark(size: 80, isUnlocked: true)),
            const SizedBox(height: AppSpacing.xl),
            FadeSlideIn(
              delay: const Duration(milliseconds: 80),
              child: Text(
                'Your vault is empty',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            FadeSlideIn(
              delay: const Duration(milliseconds: 140),
              child: Text(
                'Add a passport, licence, or any document worth keeping '
                'safe. It is encrypted before it reaches storage.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            FadeSlideIn(
              delay: const Duration(milliseconds: 200),
              child: FilledButton.icon(
                onPressed: onImport,
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Add your first document'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              size: 36,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No documents match',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: onClear,
              child: const Text('Clear search and filters'),
            ),
          ],
        ),
      ),
    );
  }
}
