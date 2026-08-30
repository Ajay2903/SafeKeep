import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:safekeep/core/constants/app_motion.dart';
import 'package:safekeep/core/constants/app_shape.dart';
import 'package:safekeep/core/constants/app_spacing.dart';
import 'package:safekeep/core/theme/app_colors.dart';
import 'package:safekeep/presentation/app/vault_session_cubit.dart';
import 'package:safekeep/presentation/widgets/fade_slide_in.dart';
import 'package:safekeep/presentation/widgets/passphrase_field.dart';
import 'package:safekeep/presentation/widgets/vault_mark.dart';
import 'package:safekeep/security/passphrase_policy.dart';

/// First-run setup: what the app does, choose a passphrase, acknowledge
/// that it cannot be recovered, then create the vault.
///
/// # Why the warning is its own step
///
/// "Your passphrase cannot be recovered" is the single most consequential
/// fact about this app, and it is the kind of sentence people skim past
/// in a paragraph of onboarding copy. It gets its own screen and requires
/// an explicit checkbox, so that forgetting the passphrase later is a
/// consequence the user accepted rather than one the app failed to
/// mention.
///
/// # Why the steps are a PageView the user cannot swipe
///
/// Physical swiping is disabled so progress is only ever made through the
/// buttons, which enforce their own preconditions — a passphrase that
/// meets policy, a confirmation that matches, an acknowledgement that was
/// actually ticked.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final _pageController = PageController();
  final _passphraseController = TextEditingController();
  final _confirmController = TextEditingController();

  int _page = 0;
  bool _acknowledged = false;
  String? _confirmError;

  @override
  void initState() {
    super.initState();
    _passphraseController.addListener(_onPassphraseChanged);
    _confirmController.addListener(_onPassphraseChanged);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _passphraseController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _onPassphraseChanged() {
    if (_confirmError != null) setState(() => _confirmError = null);
    setState(() {});
  }

  bool get _passphraseMeetsPolicy =>
      PassphrasePolicy.assess(_passphraseController.text).strength.isAcceptable;

  void _goTo(int page) {
    setState(() => _page = page);
    _pageController.animateToPage(
      page,
      duration: AppMotion.medium,
      curve: AppMotion.standard,
    );
  }

  void _submitPassphrase() {
    if (!_passphraseMeetsPolicy) return;
    if (_passphraseController.text != _confirmController.text) {
      setState(() => _confirmError = 'These do not match');
      unawaited(HapticFeedback.heavyImpact());
      return;
    }
    _goTo(2);
  }

  void _createVault() {
    unawaited(HapticFeedback.mediumImpact());
    unawaited(
      context.read<VaultSessionCubit>().createVault(
        _passphraseController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _StepIndicator(current: _page, total: 3),
            Expanded(
              child: PageView(
                controller: _pageController,
                // Buttons enforce the preconditions for each step; a
                // swipe would bypass them.
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _WelcomeStep(onContinue: () => _goTo(1)),
                  _PassphraseStep(
                    passphraseController: _passphraseController,
                    confirmController: _confirmController,
                    confirmError: _confirmError,
                    canContinue:
                        _passphraseMeetsPolicy &&
                        _confirmController.text.isNotEmpty,
                    onBack: () => _goTo(0),
                    onContinue: _submitPassphrase,
                  ),
                  _WarningStep(
                    acknowledged: _acknowledged,
                    onAcknowledgedChanged: (value) =>
                        setState(() => _acknowledged = value),
                    onBack: () => _goTo(1),
                    onCreate: _createVault,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- steps

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _StepScaffold(
      children: [
        const SizedBox(height: AppSpacing.xl),
        const Center(child: FadeSlideIn(child: VaultMark(size: 104))),
        const SizedBox(height: AppSpacing.xl),
        FadeSlideIn(
          delay: const Duration(milliseconds: 80),
          child: Text(
            'Your documents,\nsealed on this device.',
            style: theme.textTheme.displaySmall,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        FadeSlideIn(
          delay: const Duration(milliseconds: 160),
          child: Text(
            'Passports, licences, insurance, tax records — encrypted '
            'here, readable only by you.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        const _Assurance(
          delayMs: 240,
          icon: Icons.lock_outline,
          title: 'Encrypted before it touches storage',
          body: 'Nothing is ever written to disk in readable form.',
        ),
        const _Assurance(
          delayMs: 300,
          icon: Icons.cloud_off_outlined,
          title: 'No account, no server',
          body: 'Your documents never leave the device on their own.',
        ),
        const _Assurance(
          delayMs: 360,
          icon: Icons.fingerprint,
          title: 'Opens with your fingerprint',
          body: 'Your passphrase is only needed on a new device.',
        ),
        const Spacer(),
        FadeSlideIn(
          delay: const Duration(milliseconds: 420),
          child: FilledButton(
            onPressed: onContinue,
            child: const Text('Set up my vault'),
          ),
        ),
      ],
    );
  }
}

class _PassphraseStep extends StatelessWidget {
  const _PassphraseStep({
    required this.passphraseController,
    required this.confirmController,
    required this.confirmError,
    required this.canContinue,
    required this.onBack,
    required this.onContinue,
  });

  final TextEditingController passphraseController;
  final TextEditingController confirmController;
  final String? confirmError;
  final bool canContinue;
  final VoidCallback onBack;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _StepScaffold(
      onBack: onBack,
      children: [
        Text('Choose a passphrase', style: theme.textTheme.headlineMedium),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'This is what encrypts everything. Longer beats complicated — '
          'four unrelated words is stronger than a short jumble of '
          'symbols.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.xl),
        PassphraseField(
          controller: passphraseController,
          label: 'Passphrase',
          autofocus: true,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        PassphraseStrengthMeter(passphrase: passphraseController.text),
        const SizedBox(height: AppSpacing.lg),
        PassphraseField(
          controller: confirmController,
          label: 'Enter it again',
          errorText: confirmError,
          onSubmitted: (_) => onContinue(),
        ),
        const Spacer(),
        FilledButton(
          onPressed: canContinue ? onContinue : null,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class _WarningStep extends StatelessWidget {
  const _WarningStep({
    required this.acknowledged,
    required this.onAcknowledgedChanged,
    required this.onBack,
    required this.onCreate,
  });

  final bool acknowledged;
  final ValueChanged<bool> onAcknowledgedChanged;
  final VoidCallback onBack;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _StepScaffold(
      onBack: onBack,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(AppShape.radiusMedium),
          ),
          child: const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.danger,
            size: 28,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'If you forget it,\nyour documents are gone.',
          style: theme.textTheme.headlineMedium,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'There is no reset link, no recovery code, and no support team '
          'who can let you back in. That is the trade for nobody else '
          'being able to read your documents either — including us.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Write it down and keep it somewhere safe.',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.xl),
        _AcknowledgeCheckbox(
          value: acknowledged,
          onChanged: onAcknowledgedChanged,
        ),
        const Spacer(),
        FilledButton(
          onPressed: acknowledged ? onCreate : null,
          child: const Text('Create my vault'),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------- pieces

class _StepScaffold extends StatelessWidget {
  const _StepScaffold({required this.children, this.onBack});

  final List<Widget> children;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onBack != null)
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: onBack,
                tooltip: 'Back',
              ),
            ),
          Expanded(
            // Spacer needs a bounded height, but a scroll view offers an
            // unbounded one. Constraining to at least the viewport and
            // wrapping in IntrinsicHeight gives the column a real height:
            // the action button sits at the bottom on tall screens, and
            // the content scrolls instead of overflowing on short ones.
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: children,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: 'Step ${current + 1} of $total',
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: List.generate(total, (index) {
            final active = index <= current;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: index == total - 1 ? 0 : AppSpacing.xs,
                ),
                child: AnimatedContainer(
                  duration: AppMotion.medium,
                  curve: AppMotion.standard,
                  height: 3,
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.accent
                        : theme.colorScheme.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _Assurance extends StatelessWidget {
  const _Assurance({
    required this.delayMs,
    required this.icon,
    required this.title,
    required this.body,
  });

  final int delayMs;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FadeSlideIn(
      delay: Duration(milliseconds: delayMs),
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: AppColors.accent),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(body, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AcknowledgeCheckbox extends StatelessWidget {
  const _AcknowledgeCheckbox({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(AppShape.radiusMedium),
      onTap: () {
        unawaited(HapticFeedback.selectionClick());
        onChanged(!value);
      },
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value,
              onChanged: (next) => onChanged(next ?? false),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'I understand that if I forget my passphrase, my '
                'documents cannot be recovered by anyone.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
