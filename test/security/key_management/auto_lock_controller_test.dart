import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safekeep/security/key_management/auto_lock_controller.dart';
import 'package:safekeep/security/key_management/key_manager.dart';

/// Records lock() calls; the controller's only job is to call it at the
/// right time.
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
  const grace = Duration(seconds: 20);

  group('AutoLockController', () {
    test('does not lock while the app stays in the foreground', () {
      fakeAsync((async) {
        final keyManager = _SpyKeyManager();
        AutoLockController(keyManager: keyManager, gracePeriod: grace);

        async.elapse(const Duration(minutes: 10));

        expect(keyManager.lockCalls, 0);
      });
    });

    test('locks once the grace period elapses in the background', () {
      fakeAsync((async) {
        final keyManager = _SpyKeyManager();
        final controller = AutoLockController(
          keyManager: keyManager,
          gracePeriod: grace,
        )..onBackgrounded();

        async.elapse(grace + const Duration(seconds: 1));

        expect(keyManager.lockCalls, 1);
        expect(keyManager.isUnlocked, isFalse);
        expect(controller.isCountingDown, isFalse);
      });
    });

    test('does not lock before the grace period elapses', () {
      fakeAsync((async) {
        final keyManager = _SpyKeyManager();
        AutoLockController(
          keyManager: keyManager,
          gracePeriod: grace,
        ).onBackgrounded();

        async.elapse(const Duration(seconds: 19));

        expect(keyManager.lockCalls, 0);
      });
    });

    test('returning to the foreground in time cancels the lock', () {
      fakeAsync((async) {
        // The case that matters for usability: a file picker or camera
        // round trip must not force a re-unlock.
        final keyManager = _SpyKeyManager();
        final controller = AutoLockController(
          keyManager: keyManager,
          gracePeriod: grace,
        )..onBackgrounded();

        async.elapse(const Duration(seconds: 10));
        controller.onForegrounded();
        async.elapse(const Duration(minutes: 5));

        expect(keyManager.lockCalls, 0);
        expect(keyManager.isUnlocked, isTrue);
      });
    });

    test('re-backgrounding restarts the countdown', () {
      fakeAsync((async) {
        final keyManager = _SpyKeyManager();
        final controller = AutoLockController(
          keyManager: keyManager,
          gracePeriod: grace,
        )..onBackgrounded();

        async.elapse(const Duration(seconds: 15));
        controller
          ..onForegrounded()
          ..onBackgrounded();

        // 15s already elapsed, but the countdown restarted from zero.
        async.elapse(const Duration(seconds: 15));
        expect(keyManager.lockCalls, 0);

        async.elapse(const Duration(seconds: 6));
        expect(keyManager.lockCalls, 1);
      });
    });

    test('repeated backgrounding does not stack timers', () {
      fakeAsync((async) {
        final keyManager = _SpyKeyManager();
        AutoLockController(keyManager: keyManager, gracePeriod: grace)
          ..onBackgrounded()
          ..onBackgrounded()
          ..onBackgrounded();

        async.elapse(const Duration(minutes: 5));

        expect(keyManager.lockCalls, 1);
      });
    });

    test('lockNow locks immediately without waiting', () {
      fakeAsync((async) {
        final keyManager = _SpyKeyManager();
        final controller = AutoLockController(
          keyManager: keyManager,
          gracePeriod: grace,
        )..lockNow();

        expect(keyManager.lockCalls, 1);
        expect(controller.isCountingDown, isFalse);

        // And no second lock from a leftover timer.
        async.elapse(const Duration(minutes: 5));
        expect(keyManager.lockCalls, 1);
      });
    });

    test('dispose cancels a pending lock', () {
      fakeAsync((async) {
        final keyManager = _SpyKeyManager();
        AutoLockController(keyManager: keyManager, gracePeriod: grace)
          ..onBackgrounded()
          ..dispose();

        async.elapse(const Duration(minutes: 5));

        expect(keyManager.lockCalls, 0);
      });
    });

    test('default grace period is 30 seconds', () {
      expect(
        AutoLockController.defaultGracePeriod,
        const Duration(seconds: 30),
      );
    });
  });
}
