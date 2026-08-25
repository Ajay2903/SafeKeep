import 'dart:async';

import 'package:safekeep/security/key_management/key_manager.dart';

/// Locks the vault after the app has been in the background too long.
///
/// # Why a grace period rather than locking immediately
///
/// Backgrounding happens constantly for reasons that are not "the user
/// walked away": the system file picker, a camera intent, the share sheet,
/// a notification shade pull. Locking on every one of those would force a
/// biometric prompt in the middle of importing a document, which trains
/// users to disable the lock entirely. A short grace period keeps the
/// protection meaningful — a phone left on a table locks — without making
/// normal use hostile.
///
/// # Why this is driven by explicit calls
///
/// This class deliberately does **not** observe `WidgetsBinding` itself.
/// `lib/security/` stays free of Flutter UI dependencies so it remains
/// auditable and unit-testable in isolation; the UI layer owns lifecycle
/// observation and calls [onBackgrounded] / [onForegrounded]. The timing
/// policy lives here so it can be tested deterministically with fake
/// timers.
// TODO(phase2): wire onBackgrounded/onForegrounded to a
// WidgetsBindingObserver when the app shell gains an unlock screen.
class AutoLockController {
  AutoLockController({
    required KeyManager keyManager,
    Duration gracePeriod = defaultGracePeriod,
  }) : this._(keyManager, gracePeriod);

  AutoLockController._(this._keyManager, this._gracePeriod);

  /// How long the app may stay backgrounded before the vault locks.
  ///
  /// 30 seconds is long enough to cover a file picker or camera round
  /// trip, short enough that a phone put down and picked up by someone
  /// else is locked.
  static const Duration defaultGracePeriod = Duration(seconds: 30);

  final KeyManager _keyManager;
  final Duration _gracePeriod;

  Timer? _timer;

  /// Whether a lock is currently pending. Exposed for tests and
  /// diagnostics.
  bool get isCountingDown => _timer != null;

  /// Call when the app leaves the foreground.
  void onBackgrounded() {
    _timer?.cancel();
    _timer = Timer(_gracePeriod, () {
      _timer = null;
      _keyManager.lock();
    });
  }

  /// Call when the app returns to the foreground. Cancels a pending lock;
  /// if the grace period already elapsed, the vault is already locked and
  /// this does nothing.
  void onForegrounded() {
    _timer?.cancel();
    _timer = null;
  }

  /// Locks immediately, regardless of any pending timer.
  ///
  /// For an explicit "lock now" action, and for events that should never
  /// get a grace period (e.g. a screen-off or device-lock signal).
  void lockNow() {
    onForegrounded();
    _keyManager.lock();
  }

  /// Cancels any pending timer. Call when disposing the owning object.
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
