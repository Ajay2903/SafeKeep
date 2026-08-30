import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:safekeep/core/constants/app_motion.dart';
import 'package:safekeep/core/constants/app_shape.dart';
import 'package:safekeep/core/constants/app_spacing.dart';
import 'package:safekeep/core/theme/app_colors.dart';
import 'package:safekeep/presentation/app/vault_session_cubit.dart';
import 'package:safekeep/presentation/app/vault_session_state.dart';
import 'package:safekeep/presentation/widgets/fade_slide_in.dart';
import 'package:safekeep/presentation/widgets/passphrase_field.dart';
import 'package:safekeep/presentation/widgets/vault_mark.dart';
import 'package:safekeep/security/auth/biometric_gate.dart';

/// The returning-user screen: biometric unlock, with passphrase fallback.
///
/// # Why biometrics are offered but not forced
///
/// The passphrase route is always reachable, not hidden behind a failed
/// biometric attempt. Sensors fail, fingers get wet, and a user may
/// simply prefer typing. Making the fallback a visible peer of the
/// primary action means nobody is ever stuck staring at a prompt that
/// will not recognise them.
///
/// # Why a wrong passphrase says so little
///
/// The message is the same regardless of how wrong the attempt was, and
/// no attempt counter is shown. Anything more descriptive helps whoever
/// is holding the device more than it helps its owner.
class UnlockScreen extends StatefulWidget {
  const UnlockScreen({required this.state, super.key});

  final VaultLocked state;

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen>
    with SingleTickerProviderStateMixin {
  final _passphraseController = TextEditingController();
  bool _showPassphraseEntry = false;
  bool _promptedOnce = false;

  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: AppMotion.medium,
  );

  @override
  void initState() {
    super.initState();
    // Offer the biometric prompt immediately on arrival. Making the user
    // tap a button first would add a step to the single most repeated
    // action in the app.
    if (widget.state.biometricsAvailable) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometrics());
    } else {
      _showPassphraseEntry = true;
    }
  }

  @override
  void didUpdateWidget(UnlockScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If biometrics could not run at all, open the passphrase field
    // straight away: the user must never be left looking at a screen
    // whose only button does nothing.
    if (widget.state.biometricMessage != null && !_showPassphraseEntry) {
      _showPassphraseEntry = true;
    }
    if (widget.state.lastAttemptFailed && !oldWidget.state.lastAttemptFailed) {
      unawaited(HapticFeedback.heavyImpact());
      _shake.forward(from: 0);
      _passphraseController.clear();
    }
  }

  @override
  void dispose() {
    _passphraseController.dispose();
    _shake.dispose();
    super.dispose();
  }

  void _tryBiometrics() {
    if (_promptedOnce) return;
    _promptedOnce = true;
    unawaited(context.read<VaultSessionCubit>().unlockWithBiometrics());
  }

  /// Label for the unlock button, matching what the device will prompt
  /// with rather than what the feature is called internally.
  String get _unlockLabel => switch (widget.state.capability) {
    BiometricCapability.fingerprint => 'Unlock with fingerprint',
    BiometricCapability.face => 'Unlock with face',
    BiometricCapability.iris => 'Unlock with iris scan',
    BiometricCapability.deviceCredential => 'Unlock with screen lock',
    // Reached when the capability could not be determined but the gate
    // still reports itself usable. A neutral label beats a wrong one.
    BiometricCapability.none => 'Unlock',
  };

  IconData get _unlockIcon => switch (widget.state.capability) {
    BiometricCapability.fingerprint => Icons.fingerprint,
    BiometricCapability.face => Icons.face_outlined,
    BiometricCapability.iris => Icons.visibility_outlined,
    BiometricCapability.deviceCredential => Icons.pattern_outlined,
    BiometricCapability.none => Icons.lock_open_outlined,
  };

  void _submitPassphrase() {
    final passphrase = _passphraseController.text;
    if (passphrase.isEmpty) return;
    unawaited(
      context.read<VaultSessionCubit>().unlockWithPassphrase(passphrase),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Center(child: FadeSlideIn(child: VaultMark(size: 88))),
              const SizedBox(height: AppSpacing.xl),
              FadeSlideIn(
                delay: const Duration(milliseconds: 80),
                child: Text(
                  'Vault locked',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              FadeSlideIn(
                delay: const Duration(milliseconds: 140),
                child: Text(
                  widget.state.biometricsAvailable
                      ? 'Unlock with your fingerprint, or use your '
                            'passphrase.'
                      : 'Enter your passphrase to unlock.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              _ErrorBanner(visible: widget.state.lastAttemptFailed),
              AnimatedSize(
                duration: AppMotion.medium,
                curve: AppMotion.standard,
                child: _showPassphraseEntry
                    ? _PassphraseEntry(
                        controller: _passphraseController,
                        shake: _shake,
                        onSubmit: _submitPassphrase,
                      )
                    : const SizedBox(width: double.infinity),
              ),
              const Spacer(),
              if (widget.state.biometricMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: _BiometricNotice(
                    message: widget.state.biometricMessage!,
                  ),
                ),
              if (widget.state.biometricsAvailable)
                FilledButton.icon(
                  onPressed: () {
                    _promptedOnce = false;
                    _tryBiometrics();
                  },
                  // Named after what the device will actually ask for.
                  // "Unlock with biometrics" on a phone that then shows a
                  // pattern grid is the app being wrong about the user's
                  // own hardware.
                  icon: Icon(_unlockIcon, size: 22),
                  label: Text(_unlockLabel),
                ),
              if (widget.state.biometricsAvailable && !_showPassphraseEntry)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: TextButton(
                    onPressed: () =>
                        setState(() => _showPassphraseEntry = true),
                    child: const Text('Use passphrase instead'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PassphraseEntry extends StatelessWidget {
  const _PassphraseEntry({
    required this.controller,
    required this.shake,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final AnimationController shake;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shake,
      builder: (context, child) {
        // A damped horizontal wobble. Deliberately small: this is a
        // correction cue, not a scolding.
        final t = shake.value;
        final dx = t == 0 ? 0.0 : (1 - t) * 10 * _oscillate(t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Column(
        children: [
          PassphraseField(
            controller: controller,
            label: 'Passphrase',
            autofocus: true,
            onSubmitted: (_) => onSubmit(),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            onPressed: onSubmit,
            child: const Text('Unlock'),
          ),
        ],
      ),
    );
  }

  double _oscillate(double t) {
    // Three cycles across the animation, so it reads as a shake rather
    // than a single lurch.
    return (t * 3 * 2 * 3.14159).remainder(2 * 3.14159) < 3.14159 ? 1 : -1;
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedSize(
      duration: AppMotion.short,
      curve: AppMotion.standard,
      child: visible
          ? Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  'That passphrase did not work.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.danger,
                  ),
                ),
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }
}

/// Explains why biometric unlock could not be attempted.
///
/// Safe to show in full: it describes the device's configuration, not
/// anything about the vault or how close anyone is to getting in.
class _BiometricNotice extends StatelessWidget {
  const _BiometricNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppShape.radiusMedium),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(message, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
