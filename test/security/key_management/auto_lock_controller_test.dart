import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safekeep/security/key_management/auto_lock_controller.dart';
import 'package:safekeep/security/key_management/key_manager.dart';

/// Records lock() calls; the controller's only job is to call it at the
/// right moment.
class _SpyKeyManager implements KeyManager {
  int lockCalls = 0;
  bool unlocked = true;

  @override
  void lock() {
    lockCalls++;
    unlocked = false;
  }

  @override
  bool get isUnlocked => unlocked;

  @override
  Future<Uint8List> encryptionKeyFor(String keyId) async => Uint8List(32);

  @override
  Future<Uint8List> databaseKey() async => Uint8List(32);

  @override
  Future<bool> isInitialized() async => true;

  @override
  Future<void> setUpVault({required String passphrase}) async {}

  @override
  Future<bool> verifyPassphrase(String passphrase) async => true;

  @override
  Future<bool> unlockWithPassphrase(String passphrase) async => true;

  @override
  Future<bool> unlockWithBiometrics() async => true;

  @override
  Future<void> deleteVault() async {}
}

void main() {
  const background = Duration(seconds: 20);
  const idle = Duration(minutes: 2);

  AutoLockController controllerFor(_SpyKeyManager keyManager) {
    return AutoLockController(
      keyManager: keyManager,
      backgroundGracePeriod: background,
      inactivityTimeout: idle,
    );
  }

  group('backgrounding', () {
    test('does not lock while the app stays in the foreground', () {
      fakeAsync((async) {
        final keyManager = _SpyKeyManager();
        controllerFor(keyManager);

        async.elapse(const Duration(minutes: 10));

        expect(keyManager.lockCalls, 0);
      });
    });

    test('locks once the grace period elapses', () {
      fakeAsync((async) {
        final keyManager = _SpyKeyManager();
        final controller = controllerFor(keyManager)..onBackgrounded();

        async.elapse(background + const Duration(seconds: 1));

        expect(keyManager.lockCalls, 1);
        expect(keyManager.isUnlocked, isFalse);
        expect(controller.isBackgroundCountdownRunning, isFalse);
      });
    });

    test('does not lock before the grace period elapses', () {
      fakeAsync((async) {
        final keyManager = _SpyKeyManager();
        controllerFor(keyManager).onBackgrounded();

        async.elapse(const Duration(seconds: 19));

        expect(keyManager.lockCalls, 0);
      });
    });

    test('returning in time cancels the lock', () {
      fakeAsync((async) {
        // The case that matters for usability: a file picker or camera
        // round trip must not force a re-unlock.
        final keyManager = _SpyKeyManager();
        final controller = controllerFor(keyManager)..onBackgrounded();

        async.elapse(const Duration(seconds: 10));
        controller.onForegrounded();
        async.elapse(const Duration(seconds: 15));

        expect(keyManager.lockCalls, 0);
        expect(keyManager.isUnlocked, isTrue);
      });
    });

    test('re-backgrounding restarts the countdown', () {
      fakeAsync((async) {
        final keyManager = _SpyKeyManager();
        final controller = controllerFor(keyManager)..onBackgrounded();

        async.elapse(const Duration(seconds: 15));
        controller
          ..onForegrounded()
          ..onBackgrounded();

        async.elapse(const Duration(seconds: 15));
        expect(keyManager.lockCalls, 0);

        async.elapse(const Duration(seconds: 6));
        expect(keyManager.lockCalls, 1);
      });
    });

    test('repeated backgrounding does not stack timers', () {
      fakeAsync((async) {
        final keyManager = _SpyKeyManager();
        controllerFor(keyManager)
          ..onBackgrounded()
          ..onBackgrounded()
          ..onBackgrounded();

        async.elapse(const Duration(minutes: 5));

        expect(keyManager.lockCalls, 1);
      });
    });
  });

  group('inactivity', () {
    test('locks after the timeout with no interaction', () {
      fakeAsync((async) {
        final keyManager = _SpyKeyManager();
        controllerFor(keyManager).recordInteraction();

        async.elapse(idle + const Duration(seconds: 1));

        expect(keyManager.lockCalls, 1);
      });
    });

    test('interaction restarts the countdown', () {
      fakeAsync((async) {
        final keyManager = _SpyKeyManager();
        final controller = controllerFor(keyManager)..recordInteraction();

        // Touch the screen every minute for an hour.
        for (var i = 0; i < 60; i++) {
          async.elapse(const Duration(minutes: 1));
          controller.recordInteraction();
        }

        expect(keyManager.lockCalls, 0, reason: 'active use must not lock');
      });
    });

    test('no countdown is armed while already locked', () {
      fakeAsync((async) {
        final keyManager = _SpyKeyManager()..unlocked = false;
        final controller = controllerFor(keyManager)..recordInteraction();

        expect(controller.isInactivityCountdownRunning, isFalse);
        async.elapse(const Duration(hours: 1));
        expect(keyManager.lockCalls, 0);
      });
    });
  });

  group('the two triggers do not race', () {
    test('backgrounding cancels the idle countdown', () {
      fakeAsync((async) {
        // Leaving both armed would make the effective grace period
        // whichever happened to be shorter, which is unpredictable.
        final keyManager = _SpyKeyManager();
        final controller = controllerFor(keyManager)
          ..recordInteraction()
          ..onBackgrounded();
        expect(controller.isInactivityCountdownRunning, isFalse);

        async.elapse(background + const Duration(seconds: 1));
        expect(keyManager.lockCalls, 1);
      });
    });

    test('returning to the foreground restarts the idle countdown', () {
      fakeAsync((async) {
        final keyManager = _SpyKeyManager();
        final controller = controllerFor(keyManager)..onBackgrounded();

        async.elapse(const Duration(seconds: 5));
        controller.onForegrounded();

        expect(controller.isInactivityCountdownRunning, isTrue);
        async.elapse(idle + const Duration(seconds: 1));
        expect(keyManager.lockCalls, 1, reason: 'idle timer took over');
      });
    });
  });

  group('explicit control', () {
    test('lockNow locks immediately and cancels both timers', () {
      fakeAsync((async) {
        final keyManager = _SpyKeyManager();
        final controller = controllerFor(keyManager)..lockNow();

        expect(keyManager.lockCalls, 1);
        expect(controller.isBackgroundCountdownRunning, isFalse);
        expect(controller.isInactivityCountdownRunning, isFalse);

        async.elapse(const Duration(minutes: 10));
        expect(keyManager.lockCalls, 1, reason: 'no leftover timer fired');
      });
    });

    test('dispose cancels a pending lock', () {
      fakeAsync((async) {
        final keyManager = _SpyKeyManager();
        controllerFor(keyManager)
          ..onBackgrounded()
          ..dispose();

        async.elapse(const Duration(minutes: 10));

        expect(keyManager.lockCalls, 0);
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
