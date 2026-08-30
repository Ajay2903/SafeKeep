import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:safekeep/core/constants/app_spacing.dart';
import 'package:safekeep/debug/crypto_debug_cubit.dart';
import 'package:safekeep/security/auth/local_auth_biometric_gate.dart';
import 'package:safekeep/security/encryption/aes_gcm_encryption_service.dart';
import 'package:safekeep/security/key_management/flutter_secure_storage_store.dart';
import 'package:safekeep/security/key_management/vault_key_manager.dart';

/// Throwaway on-device harness for the Phase 1 crypto layer.
///
/// Not part of the product. It exists to exercise the two things unit
/// tests cannot reach — the real Keystore/Keychain and a real biometric
/// prompt — and to let the crypto be poked at by hand before any real UI
/// exists.
///
/// Delete `lib/debug/` and `lib/main_crypto_debug.dart` when the real
/// unlock screen lands.
class CryptoDebugPage extends StatelessWidget {
  const CryptoDebugPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) {
        // The REAL platform-backed implementations, on purpose.
        final keyManager = VaultKeyManager(
          store: const FlutterSecureStorageStore(),
          biometricGate: LocalAuthBiometricGate(),
        );
        final cubit = CryptoDebugCubit(
          keyManager: keyManager,
          encryption: AesGcmEncryptionService(keySource: keyManager),
          biometricGate: LocalAuthBiometricGate(),
        );
        unawaited(cubit.init());
        return cubit;
      },
      child: const _CryptoDebugView(),
    );
  }
}

class _CryptoDebugView extends StatefulWidget {
  const _CryptoDebugView();

  @override
  State<_CryptoDebugView> createState() => _CryptoDebugViewState();
}

class _CryptoDebugViewState extends State<_CryptoDebugView> {
  final _passphraseController = TextEditingController(
    text: 'correct horse battery staple',
  );

  @override
  void dispose() {
    _passphraseController.dispose();
    super.dispose();
  }

  String get _passphrase => _passphraseController.text;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CryptoDebugCubit>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Crypto debug harness'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear log',
            onPressed: cubit.clearLog,
          ),
        ],
      ),
      body: BlocBuilder<CryptoDebugCubit, CryptoDebugState>(
        builder: (context, state) {
          return Column(
            children: [
              _StatusBar(state: state),
              if (state.busy) const LinearProgressIndicator(),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: TextField(
                  controller: _passphraseController,
                  decoration: const InputDecoration(
                    labelText: 'Passphrase',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              _Actions(
                state: state,
                onSetUp: () => cubit.setUpVault(_passphrase),
                onVerify: () => cubit.verifyPassphrase(_passphrase),
                onUnlockPassphrase: () =>
                    cubit.unlockWithPassphrase(_passphrase),
                cubit: cubit,
              ),
              const Divider(height: 1),
              Expanded(child: _LogView(log: state.log)),
            ],
          );
        },
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.state});

  final CryptoDebugState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: [
          _Chip(
            label: state.vaultExists ? 'vault exists' : 'no vault',
            good: state.vaultExists,
          ),
          _Chip(
            label: state.unlocked ? 'UNLOCKED' : 'locked',
            good: state.unlocked,
          ),
          _Chip(
            label: state.biometricsAvailable ? 'biometrics' : 'no biometrics',
            good: state.biometricsAvailable,
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.good});

  final String label;
  final bool good;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: good ? scheme.primaryContainer : scheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.state,
    required this.onSetUp,
    required this.onVerify,
    required this.onUnlockPassphrase,
    required this.cubit,
  });

  final CryptoDebugState state;
  final VoidCallback onSetUp;
  final VoidCallback onVerify;
  final VoidCallback onUnlockPassphrase;
  final CryptoDebugCubit cubit;

  @override
  Widget build(BuildContext context) {
    final busy = state.busy;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: [
          FilledButton.tonal(
            onPressed: busy || state.vaultExists ? null : onSetUp,
            child: const Text('1. Set up vault'),
          ),
          FilledButton.tonal(
            onPressed: busy || !state.unlocked ? null : cubit.encryptSample,
            child: const Text('2. Encrypt 256 KB'),
          ),
          FilledButton.tonal(
            onPressed: busy || !state.unlocked ? null : cubit.lock,
            child: const Text('3. Lock'),
          ),
          FilledButton.tonal(
            onPressed: busy || !state.hasEncryptedBlob || state.unlocked
                ? null
                : cubit.tryDecryptWhileLocked,
            child: const Text('4. Try decrypt while locked'),
          ),
          FilledButton(
            onPressed: busy || !state.vaultExists || state.unlocked
                ? null
                : cubit.unlockWithBiometrics,
            child: const Text('5. Unlock (biometrics)'),
          ),
          FilledButton.tonal(
            onPressed: busy || !state.hasEncryptedBlob || !state.unlocked
                ? null
                : cubit.decryptAndVerify,
            child: const Text('6. Decrypt + verify'),
          ),
          const SizedBox(width: double.infinity, height: AppSpacing.xs),
          OutlinedButton(
            onPressed: busy || !state.vaultExists || state.unlocked
                ? null
                : onUnlockPassphrase,
            child: const Text('Unlock (passphrase)'),
          ),
          OutlinedButton(
            onPressed: busy || !state.vaultExists ? null : onVerify,
            child: const Text('Verify passphrase only'),
          ),
          OutlinedButton(
            onPressed: busy || !state.unlocked
                ? null
                : cubit.proveNonceFreshness,
            child: const Text('Prove fresh nonce'),
          ),
          OutlinedButton(
            onPressed: busy || !state.hasEncryptedBlob || !state.unlocked
                ? null
                : cubit.tamperAndDecrypt,
            child: const Text('Tamper + decrypt'),
          ),
          OutlinedButton(
            onPressed: busy || !state.unlocked
                ? null
                : cubit.proveDocumentBinding,
            child: const Text('Prove document binding'),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: busy || !state.vaultExists ? null : cubit.deleteVault,
            child: const Text('Delete vault'),
          ),
        ],
      ),
    );
  }
}

class _LogView extends StatelessWidget {
  const _LogView({required this.log});

  final List<DebugLine> log;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (log.isEmpty) {
      return const Center(child: Text('No output yet'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: log.length,
      itemBuilder: (context, index) {
        final line = log[log.length - 1 - index];
        final color = switch (line.tone) {
          LogTone.success => scheme.primary,
          LogTone.failure => scheme.error,
          LogTone.info => scheme.onSurfaceVariant,
        };
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text(
            line.millis == null
                ? line.message
                : '${line.message}  (${line.millis} ms)',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontFamily: 'monospace',
            ),
          ),
        );
      },
    );
  }
}
