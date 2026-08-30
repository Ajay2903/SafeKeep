import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safekeep/core/constants/app_motion.dart';
import 'package:safekeep/core/constants/app_shape.dart';
import 'package:safekeep/core/constants/app_spacing.dart';
import 'package:safekeep/core/theme/app_colors.dart';
import 'package:safekeep/security/passphrase_policy.dart';

/// A passphrase input with a reveal toggle.
///
/// # Why revealing is offered
///
/// Hiding input by default is right, but a vault passphrase is long and
/// unrecoverable, and a typo at setup means permanent data loss. Letting
/// someone check what they typed prevents a far worse outcome than the
/// shoulder-surfing it risks. The toggle is off by default and its state
/// is never persisted.
///
/// Autofill, autocorrect, and suggestions are all disabled: a passphrase
/// must not end up in the keyboard's learned-words dictionary or a
/// password manager's heuristic capture.
class PassphraseField extends StatefulWidget {
  const PassphraseField({
    required this.controller,
    required this.label,
    this.hint,
    this.autofocus = false,
    this.errorText,
    this.onSubmitted,
    this.enabled = true,
    this.textInputAction = TextInputAction.done,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool autofocus;
  final String? errorText;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final TextInputAction textInputAction;

  @override
  State<PassphraseField> createState() => _PassphraseFieldState();
}

class _PassphraseFieldState extends State<PassphraseField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextField(
      controller: widget.controller,
      obscureText: _obscured,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      onSubmitted: widget.onSubmitted,
      textInputAction: widget.textInputAction,
      style: theme.textTheme.bodyLarge,
      // A passphrase must not be learned by the keyboard, offered as a
      // suggestion later, or captured by an autofill heuristic.
      autocorrect: false,
      enableSuggestions: false,
      // Matches the default, but stated because it is a security choice
      // rather than a styling one: a passphrase must never be offered to
      // an autofill provider.
      // ignore: avoid_redundant_argument_values
      autofillHints: const [],
      keyboardType: TextInputType.visiblePassword,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        errorText: widget.errorText,
        suffixIcon: Semantics(
          button: true,
          label: _obscured ? 'Show passphrase' : 'Hide passphrase',
          child: IconButton(
            icon: Icon(
              _obscured
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 20,
            ),
            onPressed: widget.enabled
                ? () {
                    unawaited(HapticFeedback.selectionClick());
                    setState(() => _obscured = !_obscured);
                  }
                : null,
          ),
        ),
      ),
    );
  }
}

/// A four-segment strength indicator with a plain-language caption.
///
/// The caption deliberately talks about *length* rather than praising the
/// user, because length is the lever that actually helps and because the
/// underlying estimate has no dictionary — see [PassphrasePolicy]. A
/// meter that says "Strong!" invites more trust than this estimate has
/// earned.
class PassphraseStrengthMeter extends StatelessWidget {
  const PassphraseStrengthMeter({required this.passphrase, super.key});

  final String passphrase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final assessment = PassphrasePolicy.assess(passphrase);
    final filled = _filledSegments(assessment.strength);
    final color = _colorFor(assessment.strength, theme);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(4, (index) {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: index == 3 ? 0 : AppSpacing.xs),
                child: AnimatedContainer(
                  duration: AppMotion.short,
                  curve: AppMotion.standard,
                  height: 4,
                  decoration: BoxDecoration(
                    color: index < filled ? color : theme.colorScheme.outline,
                    borderRadius: BorderRadius.circular(AppShape.radiusSmall),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: AppSpacing.sm),
        AnimatedSwitcher(
          duration: AppMotion.short,
          child: Text(
            _captionFor(assessment, passphrase),
            key: ValueKey(assessment.strength),
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }

  int _filledSegments(PassphraseStrength strength) => switch (strength) {
    PassphraseStrength.tooShort => 0,
    PassphraseStrength.weak => 1,
    PassphraseStrength.fair => 2,
    PassphraseStrength.strong => 3,
    PassphraseStrength.excellent => 4,
  };

  Color _colorFor(PassphraseStrength strength, ThemeData theme) {
    return switch (strength) {
      PassphraseStrength.tooShort ||
      PassphraseStrength.weak => AppColors.danger,
      PassphraseStrength.fair => theme.colorScheme.onSurfaceVariant,
      PassphraseStrength.strong ||
      PassphraseStrength.excellent => AppColors.success,
    };
  }

  String _captionFor(PassphraseAssessment assessment, String passphrase) {
    if (passphrase.isEmpty) {
      return 'Use at least ${PassphrasePolicy.minimumLength} characters. '
          'A few unrelated words works well.';
    }
    return switch (assessment.strength) {
      PassphraseStrength.tooShort =>
        '${PassphrasePolicy.minimumLength - passphrase.length} more '
            'characters needed',
      PassphraseStrength.weak => 'Weak — add more length, not more symbols',
      PassphraseStrength.fair => 'Fair — longer would be meaningfully better',
      PassphraseStrength.strong => 'Strong',
      PassphraseStrength.excellent => 'Excellent',
    };
  }
}
