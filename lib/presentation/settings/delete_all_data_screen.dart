import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:safekeep/core/constants/app_shape.dart';
import 'package:safekeep/core/constants/app_spacing.dart';
import 'package:safekeep/core/theme/app_colors.dart';
import 'package:safekeep/presentation/app/vault_session_cubit.dart';
import 'package:safekeep/presentation/widgets/passphrase_field.dart';

/// Confirms and performs an irreversible erase of everything.
///
/// # Why this is a screen and not a dialog
///
/// The action destroys every document with no backup and no undo. A
/// dialog is something people dismiss reflexively; a screen has to be
/// navigated to, read, and deliberately completed. The user passes three
/// gates: reaching this screen, ticking an acknowledgement, and entering
/// their passphrase.
///
/// # Why the passphrase, and not biometrics
///
/// Biometrics prove the phone is in the right hands, which is a weaker
/// claim than it sounds — a device handed over unlocked, or a sleeping
/// owner's finger, both pass. The passphrase is the one thing only the
/// owner knows, and destroying a vault is exactly where that distinction
/// should matter. It is verified against the stored verifier, so a wrong
/// entry costs nothing.
class DeleteAllDataScreen extends StatefulWidget {
  const DeleteAllDataScreen({super.key});

  @override
  State<DeleteAllDataScreen> createState() => _DeleteAllDataScreenState();
}

class _DeleteAllDataScreenState extends State<DeleteAllDataScreen> {
  final _passphraseController = TextEditingController();
  bool _acknowledged = false;
  bool _busy = false;
  bool _wrongPassphrase = false;

  @override
  void initState() {
    super.initState();
    // The field has no onChanged, so listen directly — the submit button
    // stays disabled until something has actually been typed.
    _passphraseController.addListener(_onPassphraseChanged);
  }

  void _onPassphraseChanged() => setState(() {});

  @override
  void dispose() {
    _passphraseController
      ..removeListener(_onPassphraseChanged)
      ..dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _acknowledged && _passphraseController.text.isNotEmpty && !_busy;

  Future<void> _confirmAndErase() async {
    // The last gate. Everything before this was reversible; this is not.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(
          Icons.warning_amber_rounded,
          color: AppColors.danger,
          size: 32,
        ),
        title: const Text('Erase everything?'),
        content: const Text(
          'Every document and its encryption key will be destroyed. This '
          'cannot be undone, and nothing can recover them afterwards — '
          'not us, not your passphrase.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep my data'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Erase everything'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) return;

    setState(() {
      _busy = true;
      _wrongPassphrase = false;
    });

    final erased = await context.read<VaultSessionCubit>().deleteEverything(
      _passphraseController.text,
    );
    if (!mounted) return;

    if (!erased) {
      setState(() {
        _busy = false;
        _wrongPassphrase = true;
        _passphraseController.clear();
      });
      return;
    }
    // On success the session cubit emits VaultUninitialized and the gate
    // replaces this whole subtree with onboarding, so there is nothing
    // to navigate back to.
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Delete all data')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(AppShape.radiusMedium),
              border: Border.all(
                color: AppColors.danger.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This is permanent',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppColors.danger,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Continuing will erase, from this device:',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                const _EraseItem('Every document you have stored'),
                const _EraseItem('The encryption key that opens them'),
                const _EraseItem('All expiry reminders'),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'There is no backup and no recovery. Because your documents '
            'are encrypted with a key only you hold, nobody — including '
            'us — can restore them once the key is gone.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          CheckboxListTile(
            value: _acknowledged,
            onChanged: _busy
                ? null
                : (value) => setState(() => _acknowledged = value ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              'I understand my documents cannot be recovered',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Enter your passphrase to confirm',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Your fingerprint is not enough for this. Only the passphrase '
            'proves it is you.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          PassphraseField(
            controller: _passphraseController,
            label: 'Passphrase',
            enabled: !_busy,
            errorText: _wrongPassphrase
                ? 'That passphrase is not correct.'
                : null,
            onSubmitted: _canSubmit ? (_) => _confirmAndErase() : null,
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              disabledBackgroundColor: theme.colorScheme.outline,
            ),
            onPressed: _canSubmit ? _confirmAndErase : null,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Delete all data'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

class _EraseItem extends StatelessWidget {
  const _EraseItem(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.close, size: 14, color: AppColors.danger),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
