import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:safekeep/core/constants/app_spacing.dart';
import 'package:safekeep/presentation/app/vault_session_cubit.dart';
import 'package:safekeep/presentation/widgets/fade_slide_in.dart';
import 'package:safekeep/presentation/widgets/vault_mark.dart';

/// The screen behind the lock.
///
/// Phase 3 only proves the door works, so this is deliberately a
/// placeholder: it confirms the vault is open and offers an explicit
/// lock. The document list, viewer, and import flows are Phase 4, which
/// is when this file gets replaced rather than extended.
class VaultHomeScreen extends StatelessWidget {
  const VaultHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FadeSlideIn(
                child: VaultMark(size: 88, isUnlocked: true),
              ),
              const SizedBox(height: AppSpacing.xl),
              FadeSlideIn(
                delay: const Duration(milliseconds: 80),
                child: Text(
                  'Your vault is open',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              FadeSlideIn(
                delay: const Duration(milliseconds: 140),
                child: Text(
                  'Documents arrive in the next phase. The encryption, '
                  'storage, and lock behind this screen are already '
                  'working.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              FadeSlideIn(
                delay: const Duration(milliseconds: 200),
                child: OutlinedButton.icon(
                  onPressed: () => context.read<VaultSessionCubit>().lock(),
                  icon: const Icon(Icons.lock_outline, size: 20),
                  label: const Text('Lock now'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
