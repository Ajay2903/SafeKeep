import 'dart:async';

import 'package:safekeep/security/key_management/key_manager.dart';

/// Decides when an unattended vault should seal itself.
///
/// Two independent triggers, because "unattended" has two shapes:
///
/// * **Backgrounded** — the app left the foreground and did not come
///   back. Gets a short grace period.
/// * **Idle** — the app is in front of the user but nothing has been
///   touched. Gets a longer one.
///
/// # Why the background trigger has a grace period at all
///
/// Backgrounding happens constantly for reasons that are not "the user
/// walked away": the system file picker, a camera intent, the share
/// sheet, a notification shade pull. Locking on every one would force a
/// biometric prompt in the middle of importing a document, which trains
/// people to disable the lock entirely. A short grace period keeps the
/// protection meaningful — a phone left on a table locks — without making
/// normal use hostile.
///
/// # Why this is driven by explicit calls
///
/// This class deliberately does not observe `WidgetsBinding` itself.
/// `lib/security/` stays free of Flutter UI dependencies so it remains
/// auditable and unit-testable in isolation; the presentation layer owns
/// lifecycle and gesture observation and calls in here. The timing policy
/// lives here so it can be tested deterministically with fake timers.
class AutoLockController {
  AutoLockController({
    required KeyManager keyManager,
    Duration backgroundGracePeriod = defaultBackgroundGracePeriod,
    Duration inactivityTimeout = defaultInactivityTimeout,
  }) : this._(keyManager, backgroundGracePeriod, inactivityTimeout);

  AutoLockController._(
    this._keyManager,
    this._backgroundGracePeriod,
    this._inactivityTimeout,
  );

  /// How long the app may stay backgrounded before the vault locks.
  ///
  /// 30 seconds covers a file picker or camera round trip while still
  /// locking a phone that has been put down and picked up by someone
  /// else.
  static const Duration defaultBackgroundGracePeriod = Duration(seconds: 30);

  /// How long the app may sit untouched in the foreground before locking.
  ///
  /// Longer than the background period: the user is plausibly still
  /// present, perhaps reading a document on screen. Short enough that a
  /// vault left open on an unattended desk does not stay open.
  static const Duration defaultInactivityTimeout = Duration(minutes: 3);

  final KeyManager _keyManager;
  final Duration _backgroundGracePeriod;
  final Duration _inactivityTimeout;

  Timer? _backgroundTimer;
  Timer? _inactivityTimer;

  /// Whether a background lock is pending. Exposed for tests.
  bool get isBackgroundCountdownRunning => _backgroundTimer != null;

  /// Whether an inactivity lock is pending. Exposed for tests.
  bool get isInactivityCountdownRunning => _inactivityTimer != null;

  /// Call when the app leaves the foreground.
  void onBackgrounded() {
    // The idle timer is meaningless while backgrounded; the background
    // timer supersedes it. Leaving both armed would lock on whichever
    // fired first, making the effective grace period unpredictable.
    _inactivityTimer?.cancel();
    _inactivityTimer = null;

    _backgroundTimer?.cancel();
    _backgroundTimer = Timer(_backgroundGracePeriod, () {
      _backgroundTimer = null;
      _keyManager.lock();
    });
  }

  /// Call when the app returns to the foreground.
  ///
  /// Cancels a pending background lock. If the grace period already
  /// elapsed the vault is locked and this changes nothing.
  void onForegrounded() {
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
    recordInteraction();
  }

  /// Call on any user interaction to restart the idle countdown.
  ///
  /// Cheap by design — this runs on every pointer event, so it must not
  /// allocate or do work beyond resetting a timer. No timer is armed when
  /// the vault is already locked, since there would be nothing to lock.
  void recordInteraction() {
    _inactivityTimer?.cancel();
    if (!_keyManager.isUnlocked) {
      _inactivityTimer = null;
      return;
    }
    _inactivityTimer = Timer(_inactivityTimeout, () {
      _inactivityTimer = null;
      _keyManager.lock();
    });
  }

  /// Locks immediately, cancelling both countdowns.
  ///
  /// For an explicit "lock now" action, and for events that should never
  /// get a grace period — a screen-off or device-lock signal.
  void lockNow() {
    _cancelAll();
    _keyManager.lock();
  }

  /// Cancels pending timers. Call when disposing the owner.
  void dispose() => _cancelAll();

  void _cancelAll() {
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
  }
}
