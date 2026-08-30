import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:safekeep/core/constants/app_motion.dart';
import 'package:safekeep/core/constants/app_spacing.dart';
import 'package:safekeep/data/database/settings_dao.dart';
import 'package:safekeep/data/reminders/reminder_scheduler.dart';
import 'package:safekeep/data/scanning/document_scanner.dart';
import 'package:safekeep/domain/repositories/document_repository.dart';
import 'package:safekeep/presentation/app/vault_session_cubit.dart';
import 'package:safekeep/presentation/app/vault_session_state.dart';
import 'package:safekeep/presentation/onboarding/onboarding_flow.dart';
import 'package:safekeep/presentation/unlock/unlock_screen.dart';
import 'package:safekeep/presentation/vault/vault_home_screen.dart';
import 'package:safekeep/presentation/widgets/vault_mark.dart';

/// Chooses what the app shows, and enforces that unlocked screens exist
/// only while the vault is unlocked.
///
/// # Why this replaces routing for the lock boundary
///
/// The screen is selected by *state*, not pushed onto a navigator. When
/// the vault locks, the unlocked subtree is removed from the widget tree
/// entirely — its state, its controllers, and anything it had decrypted
/// into memory go with it. A navigation-based lock would depend on every
/// path remembering to pop, and there is always one that does not.
///
/// # What it observes
///
/// * **App lifecycle** — backgrounding starts the grace-period countdown.
/// * **Pointer events** — any touch defers the idle countdown.
///
/// Both are captured here, at the root, so no screen has to remember to
/// participate.
class VaultGate extends StatefulWidget {
  const VaultGate({
    required this.repository,
    required this.scanner,
    required this.settingsDao,
    required this.reminders,
    super.key,
  });

  /// The vault, handed to the unlocked screens. Constructed above this
  /// widget so the whole tree can be built with fakes in a test.
  final DocumentRepository repository;

  /// Behind an interface so a poor-quality scanner package can be
  /// swapped without touching any of this.
  final DocumentScanner scanner;

  final SettingsDao settingsDao;
  final ReminderScheduler reminders;

  @override
  State<VaultGate> createState() => _VaultGateState();
}

class _VaultGateState extends State<VaultGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(context.read<VaultSessionCubit>().checkStatus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cubit = context.read<VaultSessionCubit>();
    switch (state) {
      case AppLifecycleState.resumed:
        cubit.onAppForegrounded();
      case AppLifecycleState.inactive:
      // `inactive` fires for transient interruptions (a notification
      // shade pull, the app switcher opening) as well as real departures,
      // so it is not treated as backgrounding — doing so would start the
      // countdown every time a banner appeared.
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        cubit.onAppBackgrounded();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      // Deferring the idle lock on any pointer down, at the root, so no
      // screen has to opt in. Listener rather than GestureDetector so it
      // observes without competing in the gesture arena — this must never
      // swallow a tap meant for a button.
      onPointerDown: (_) =>
          context.read<VaultSessionCubit>().recordInteraction(),
      child: BlocBuilder<VaultSessionCubit, VaultSessionState>(
        builder: (context, state) {
          return AnimatedSwitcher(
            duration: AppMotion.medium,
            switchInCurve: AppMotion.enter,
            switchOutCurve: AppMotion.exit,
            // Cross-fade without sliding: a lock is not a navigation, and
            // sliding would imply the previous screen still exists
            // somewhere to go back to.
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: KeyedSubtree(
              key: ValueKey(state.runtimeType),
              child: _screenFor(state),
            ),
          );
        },
      ),
    );
  }

  Widget _screenFor(VaultSessionState state) {
    return switch (state) {
      VaultChecking() => const _SplashScreen(),
      VaultUninitialized() => const OnboardingFlow(),
      VaultSettingUp() => const _WorkingScreen(
        message: 'Creating your vault',
        detail:
            'Deriving your key. This takes a moment by design — it '
            'is what makes guessing your passphrase expensive.',
      ),
      VaultUnlocking() => const _WorkingScreen(
        message: 'Unlocking',
        detail: 'Checking your passphrase.',
      ),
      final VaultLocked locked => UnlockScreen(state: locked),
      VaultUnlocked() => VaultHomeScreen(
        repository: widget.repository,
        scanner: widget.scanner,
        settingsDao: widget.settingsDao,
        reminders: widget.reminders,
      ),
    };
  }
}

/// Shown for the frame or two it takes to read whether a vault exists.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: VaultMark(size: 88)));
  }
}

/// Shown while Argon2id runs.
///
/// Explains *why* it is slow rather than showing a bare spinner. A
/// multi-second wait with no explanation reads as the app being broken;
/// the same wait, explained, reads as the app doing serious work.
class _WorkingScreen extends StatelessWidget {
  const _WorkingScreen({required this.message, required this.detail});

  final String message;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const VaultMark(size: 88, isBusy: true),
              const SizedBox(height: AppSpacing.xl),
              Text(
                message,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                detail,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
