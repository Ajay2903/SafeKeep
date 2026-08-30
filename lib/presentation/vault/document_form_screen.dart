import 'package:flutter/material.dart';
import 'package:safekeep/core/constants/app_shape.dart';
import 'package:safekeep/core/constants/app_spacing.dart';
import 'package:safekeep/core/theme/app_colors.dart';
import 'package:safekeep/domain/models/document.dart';
import 'package:safekeep/domain/models/document_category.dart';
import 'package:safekeep/presentation/vault/document_visuals.dart';

/// The metadata a document form produces.
class DocumentFormResult {
  const DocumentFormResult({
    required this.title,
    required this.category,
    required this.tags,
    this.notes,
    this.expiresAt,
  });

  final String title;
  final DocumentCategory category;
  final List<String> tags;
  final String? notes;
  final DateTime? expiresAt;
}

/// Collects a document's metadata, for both import and later editing.
///
/// One screen for both so the two can never drift apart — a field added
/// for import that editing cannot change would leave documents with
/// metadata their owner is unable to correct.
class DocumentFormScreen extends StatefulWidget {
  const DocumentFormScreen({
    required this.title,
    required this.submitLabel,
    this.initial,
    this.fileSummary,
    this.suggestedTitle,
    super.key,
  });

  /// App bar title, e.g. "Add document" or "Edit details".
  final String title;

  final String submitLabel;

  /// Existing metadata when editing; null when importing.
  final Document? initial;

  /// A short description of the file being imported, shown so the user
  /// can confirm they picked the right one before naming it.
  final String? fileSummary;

  /// Pre-filled title for a new document, e.g. an imported file's name
  /// minus its extension. Empty for a scan, which has no useful name to
  /// borrow — better a blank field than "scan_20260826".
  final String? suggestedTitle;

  @override
  State<DocumentFormScreen> createState() => _DocumentFormScreenState();
}

class _DocumentFormScreenState extends State<DocumentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  final _tagController = TextEditingController();

  late DocumentCategory _category;
  late List<String> _tags;
  DateTime? _expiresAt;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _titleController = TextEditingController(
      text: initial?.title ?? widget.suggestedTitle ?? '',
    );
    _notesController = TextEditingController(text: initial?.notes ?? '');
    _category = initial?.category ?? DocumentCategory.identity;
    _tags = List<String>.from(initial?.tags ?? const []);
    _expiresAt = initial?.expiresAt;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  void _addTag() {
    final tag = _tagController.text.trim();
    // Case-insensitive de-duplication: "Travel" and "travel" as separate
    // tags would split search results for no reason.
    if (tag.isEmpty || _tags.any((t) => t.toLowerCase() == tag.toLowerCase())) {
      _tagController.clear();
      return;
    }
    setState(() {
      _tags = [..._tags, tag];
      _tagController.clear();
    });
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? now,
      // Expiry dates are almost always in the future, but a past one is
      // allowed so an already-expired document can be recorded as such.
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 50),
    );
    if (picked != null) setState(() => _expiresAt = picked);
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      DocumentFormResult(
        title: _titleController.text.trim(),
        category: _category,
        tags: _tags,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        expiresAt: _expiresAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            if (widget.fileSummary != null) ...[
              _FileSummary(summary: widget.fileSummary!),
              const SizedBox(height: AppSpacing.lg),
            ],
            TextFormField(
              controller: _titleController,
              autofocus: widget.initial == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'Passport — Ajay',
              ),
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Give this document a name'
                  : null,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Category', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            _CategoryPicker(
              selected: _category,
              onSelected: (category) => setState(() => _category = category),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Tags', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            _TagEditor(
              tags: _tags,
              controller: _tagController,
              onAdd: _addTag,
              onRemove: (tag) => setState(
                () => _tags = _tags.where((t) => t != tag).toList(),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _ExpiryPicker(
              expiresAt: _expiresAt,
              onPick: _pickExpiry,
              onClear: () => setState(() => _expiresAt = null),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _notesController,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: _submit,
              child: Text(widget.submitLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileSummary extends StatelessWidget {
  const _FileSummary({required this.summary});

  final String summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppShape.radiusMedium),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.insert_drive_file_outlined,
            size: 20,
            color: AppColors.accent,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              summary,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({required this.selected, required this.onSelected});

  final DocumentCategory selected;
  final ValueChanged<DocumentCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final category in DocumentCategory.values)
          ChoiceChip(
            selected: category == selected,
            onSelected: (_) => onSelected(category),
            avatar: Icon(category.icon, size: 16),
            label: Text(category.label),
          ),
      ],
    );
  }
}

class _TagEditor extends StatelessWidget {
  const _TagEditor({
    required this.tags,
    required this.controller,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> tags;
  final TextEditingController controller;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (tags.isNotEmpty) ...[
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final tag in tags)
                InputChip(
                  label: Text(tag),
                  onDeleted: () => onRemove(tag),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onAdd(),
                decoration: const InputDecoration(
                  hintText: 'Add a tag',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              tooltip: 'Add tag',
            ),
          ],
        ),
      ],
    );
  }
}

class _ExpiryPicker extends StatelessWidget {
  const _ExpiryPicker({
    required this.expiresAt,
    required this.onPick,
    required this.onClear,
  });

  final DateTime? expiresAt;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Expiry date', style: theme.textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(
                expiresAt == null
                    ? 'Not set — no reminder will be scheduled'
                    : formatDate(expiresAt!),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (expiresAt != null)
          IconButton(
            onPressed: onClear,
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Clear expiry date',
          ),
        TextButton(
          onPressed: onPick,
          child: Text(expiresAt == null ? 'Set' : 'Change'),
        ),
      ],
    );
  }
}
