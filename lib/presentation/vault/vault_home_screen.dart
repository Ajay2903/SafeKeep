import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:safekeep/core/constants/app_motion.dart';
import 'package:safekeep/core/constants/app_spacing.dart';
import 'package:safekeep/data/mime_types.dart';
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
  const VaultHomeScreen({required this.repository, super.key});

  final DocumentRepository repository;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) {
        final cubit = DocumentListCubit(repository: repository);
        unawaited(cubit.load());
        return cubit;
      },
      child: _VaultHomeView(repository: repository),
    );
  }
}

class _VaultHomeView extends StatefulWidget {
  const _VaultHomeView({required this.repository});

  final DocumentRepository repository;

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

    final result = await Navigator.of(context).push<DocumentFormResult>(
      MaterialPageRoute(
        builder: (_) => DocumentFormScreen(
          title: 'Add document',
          submitLabel: 'Encrypt and save',
          fileSummary: '${file.name} · ${formatFileSize(bytes.length)}',
        ),
      ),
    );
    if (result == null || !mounted) return;

    try {
      await widget.repository.addDocument(
        bytes: bytes,
        title: result.title,
        category: result.category,
        mimeType: MimeTypes.forFileName(file.name),
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
        onPressed: () => unawaited(_import()),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: BlocBuilder<DocumentListCubit, DocumentListState>(
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.isVaultEmpty) {
            return _EmptyVault(onImport: () => unawaited(_import()));
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
      child: Padding(
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
