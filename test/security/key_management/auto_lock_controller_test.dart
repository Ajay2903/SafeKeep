import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safekeep/security/key_management/auto_lock_controller.dart';

/// Stands in for whatever owns locking. The controller decides *when*;
/// this records that it was told to.
class _LockSpy {
  int lockCalls = 0;
  bool unlocked = true;

  void lock() {
    lockCalls++;
    unlocked = false;
  }

  bool get isUnlocked => unlocked;
}

void main() {
  const background = Duration(seconds: 20);
  const idle = Duration(minutes: 2);

  AutoLockController controllerFor(_LockSpy spy) {
    return AutoLockController(
      onLock: spy.lock,
      isUnlocked: () => spy.isUnlocked,
      backgroundGracePeriod: background,
      inactivityTimeout: idle,
    );
  }

  group('backgrounding', () {
    test('does not lock while the app stays in the foreground', () {
      fakeAsync((async) {
        final spy = _LockSpy();
        controllerFor(spy);

        async.elapse(const Duration(minutes: 10));

        expect(spy.lockCalls, 0);
      });
    });

    test('locks once the grace period elapses', () {
      fakeAsync((async) {
        final spy = _LockSpy();
        final controller = controllerFor(spy)..onBackgrounded();

        async.elapse(background + const Duration(seconds: 1));

        expect(spy.lockCalls, 1);
        expect(spy.isUnlocked, isFalse);
        expect(controller.isBackgroundCountdownRunning, isFalse);
      });
    });

    test('does not lock before the grace period elapses', () {
      fakeAsync((async) {
        final spy = _LockSpy();
        controllerFor(spy).onBackgrounded();

        async.elapse(const Duration(seconds: 19));

        expect(spy.lockCalls, 0);
      });
    });

    test('returning in time cancels the lock', () {
      fakeAsync((async) {
        // The case that matters for usability: a file picker or camera
        // round trip must not force a re-unlock.
        final spy = _LockSpy();
        final controller = controllerFor(spy)..onBackgrounded();

        async.elapse(const Duration(seconds: 10));
        controller.onForegrounded();
        async.elapse(const Duration(seconds: 15));

        expect(spy.lockCalls, 0);
        expect(spy.isUnlocked, isTrue);
      });
    });

    test('re-backgrounding restarts the countdown', () {
      fakeAsync((async) {
        final spy = _LockSpy();
        final controller = controllerFor(spy)..onBackgrounded();

        async.elapse(const Duration(seconds: 15));
        controller
          ..onForegrounded()
          ..onBackgrounded();

        async.elapse(const Duration(seconds: 15));
        expect(spy.lockCalls, 0);

        async.elapse(const Duration(seconds: 6));
        expect(spy.lockCalls, 1);
      });
    });

    test('repeated backgrounding does not stack timers', () {
      fakeAsync((async) {
        final spy = _LockSpy();
        controllerFor(spy)
          ..onBackgrounded()
          ..onBackgrounded()
          ..onBackgrounded();

        async.elapse(const Duration(minutes: 5));

        expect(spy.lockCalls, 1);
      });
    });
  });

  group('inactivity', () {
    test('locks after the timeout with no interaction', () {
      fakeAsync((async) {
        final spy = _LockSpy();
        controllerFor(spy).recordInteraction();

        async.elapse(idle + const Duration(seconds: 1));

        expect(spy.lockCalls, 1);
      });
    });

    test('interaction restarts the countdown', () {
      fakeAsync((async) {
        final spy = _LockSpy();
        final controller = controllerFor(spy)..recordInteraction();

        // Touch the screen every minute for an hour.
        for (var i = 0; i < 60; i++) {
          async.elapse(const Duration(minutes: 1));
          controller.recordInteraction();
        }

        expect(spy.lockCalls, 0, reason: 'active use must not lock');
      });
    });

    test('no countdown is armed while already locked', () {
      fakeAsync((async) {
        final spy = _LockSpy()..unlocked = false;
        final controller = controllerFor(spy)..recordInteraction();

        expect(controller.isInactivityCountdownRunning, isFalse);
        async.elapse(const Duration(hours: 1));
        expect(spy.lockCalls, 0);
      });
    });
  });

  group('the two triggers do not race', () {
    test('backgrounding cancels the idle countdown', () {
      fakeAsync((async) {
        // Leaving both armed would make the effective grace period
        // whichever happened to be shorter, which is unpredictable.
        final spy = _LockSpy();
        final controller = controllerFor(spy)
          ..recordInteraction()
          ..onBackgrounded();
        expect(controller.isInactivityCountdownRunning, isFalse);

        async.elapse(background + const Duration(seconds: 1));
        expect(spy.lockCalls, 1);
      });
    });

    test('returning to the foreground restarts the idle countdown', () {
      fakeAsync((async) {
        final spy = _LockSpy();
        final controller = controllerFor(spy)..onBackgrounded();

        async.elapse(const Duration(seconds: 5));
        controller.onForegrounded();

        expect(controller.isInactivityCountdownRunning, isTrue);
        async.elapse(idle + const Duration(seconds: 1));
        expect(spy.lockCalls, 1, reason: 'idle timer took over');
      });
    });
  });

  group('explicit control', () {
    test('lockNow locks immediately and cancels both timers', () {
      fakeAsync((async) {
        final spy = _LockSpy();
        final controller = controllerFor(spy)..lockNow();

        expect(spy.lockCalls, 1);
        expect(controller.isBackgroundCountdownRunning, isFalse);
        expect(controller.isInactivityCountdownRunning, isFalse);

        async.elapse(const Duration(minutes: 10));
        expect(spy.lockCalls, 1, reason: 'no leftover timer fired');
      });
    });

    test('dispose cancels a pending lock', () {
      fakeAsync((async) {
        final spy = _LockSpy();
        controllerFor(spy)
          ..onBackgrounded()
          ..dispose();

        async.elapse(const Duration(minutes: 10));

        expect(spy.lockCalls, 0);
      });
    });
  });

  group('defaults', () {
    test('background grace period is 30 seconds', () {
      expect(
        AutoLockController.defaultBackgroundGracePeriod,
        const Duration(seconds: 30),
      );
    });

    test('idling gets more slack than walking away', () {
      // The user is plausibly still present when idle in the foreground.
      expect(
        AutoLockController.defaultInactivityTimeout,
        greaterThan(AutoLockController.defaultBackgroundGracePeriod),
      );
    });
  });
}
