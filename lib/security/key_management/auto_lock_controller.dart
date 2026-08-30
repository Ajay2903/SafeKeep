import 'dart:async';

import 'package:flutter/foundation.dart' show VoidCallback;

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
/// This class deliberately does not observe `WidgetsBinding` itself. The
/// presentation layer owns lifecycle and gesture observation and calls in
/// here; the timing policy lives here so it can be tested
/// deterministically with fake timers rather than by waiting minutes.
///
/// # Why it reports rather than locks
///
/// It invokes its `onLock` callback instead of calling
/// `KeyManager.lock()` directly.
/// Locking the vault is more than clearing key material — the metadata
/// database has to be closed and the UI has to leave every screen that
/// shows decrypted content. Calling the key manager from here would seal
/// the key while leaving the rest of the app believing it was still
/// unlocked. The owner decides what locking means; this class only
/// decides *when*.
class AutoLockController {
  AutoLockController({
    required VoidCallback onLock,
    required bool Function() isUnlocked,
    Duration backgroundGracePeriod = defaultBackgroundGracePeriod,
    Duration inactivityTimeout = defaultInactivityTimeout,
  }) : this._(onLock, isUnlocked, backgroundGracePeriod, inactivityTimeout);

  AutoLockController._(
    this._onLock,
    this._isUnlocked,
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

  final VoidCallback _onLock;
  final bool Function() _isUnlocked;
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
      _onLock();
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
    if (!_isUnlocked()) {
      _inactivityTimer = null;
      return;
    }
    _inactivityTimer = Timer(_inactivityTimeout, () {
      _inactivityTimer = null;
      _onLock();
    });
  }

  /// Locks immediately, cancelling both countdowns.
  ///
  /// For an explicit "lock now" action, and for events that should never
  /// get a grace period — a screen-off or device-lock signal.
  void lockNow() {
    _cancelAll();
    _onLock();
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
