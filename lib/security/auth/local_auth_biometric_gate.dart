import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:safekeep/core/logging/app_logger.dart';
import 'package:safekeep/security/auth/biometric_gate.dart';

/// [BiometricGate] backed by `local_auth`.
///
/// Like the secure-storage wrapper, this is intentionally thin: platform
/// channels cannot run under `flutter test`, so logic placed here would be
/// untested. Everything that decides *what to do* with the result lives in
/// `VaultKeyManager`.
///
/// # Option choices
///
/// * `biometricOnly: false` — falls back to the device PIN/pattern/
///   passcode. Requiring biometrics outright would lock out users whose
///   device has none enrolled, or whose fingerprint reader fails, and a
///   device credential is still a meaningful authentication factor.
/// * `sensitiveTransaction: true` — asks platforms that support it to show
///   the stronger confirmation UI. Unlocking a document vault qualifies.
/// * `persistAcrossBackgrounding: false` — an authentication interrupted by
///   backgrounding fails rather than silently resuming when the user
///   returns. Auto-resume would mean a prompt raised before the app was
///   backgrounded could be satisfied afterwards, which is exactly the
///   window an attacker who picks up an unattended phone would want.
///
/// # Failure handling
///
/// `local_auth` throws `PlatformException` for conditions such as no
/// enrolled credential or locked-out hardware. These are translated into
/// [BiometricUnavailableException] with a message the user can act on,
/// and are deliberately distinct from `false`, which means only that the
/// user dismissed the prompt.
///
/// Only the error *code* is logged, never the platform's message: codes
/// are a fixed vocabulary carrying no device or credential detail, while
/// messages are free text from the OS.
// NOTE: needs on-device verification; a real biometric prompt cannot be
// exercised from a unit test. See ARCHITECTURE.md's manual checklist.
class LocalAuthBiometricGate implements BiometricGate {
  LocalAuthBiometricGate({LocalAuthentication? localAuth})
    : _localAuth = localAuth ?? LocalAuthentication();

  final LocalAuthentication _localAuth;

  @override
  Future<bool> isAvailable() async {
    try {
      // isDeviceSupported() covers biometrics *or* a device credential,
      // which matches the biometricOnly: false policy below.
      return await _localAuth.isDeviceSupported();
    } on Exception {
      return false;
    }
  }

  @override
  Future<BiometricCapability> capability() async {
    try {
      final enrolled = await _localAuth.getAvailableBiometrics();

      // Ordered by how recognisably a user would name it. `strong` and
      // `weak` are Android's assurance classes rather than modalities —
      // they say nothing about what the sensor is — so a device
      // reporting only those falls through to the generic label rather
      // than being guessed at.
      if (enrolled.contains(BiometricType.face)) {
        return BiometricCapability.face;
      }
      if (enrolled.contains(BiometricType.fingerprint)) {
        return BiometricCapability.fingerprint;
      }
      if (enrolled.contains(BiometricType.iris)) {
        return BiometricCapability.iris;
      }

      // Nothing biometric is usable, but the device may still have a
      // screen lock — which is what the prompt will actually ask for.
      return await _localAuth.isDeviceSupported()
          ? BiometricCapability.deviceCredential
          : BiometricCapability.none;
    } on PlatformException catch (error) {
      AppLogger.instance.warning(
        'Biometric capability unknown: '
        '${error.code}',
      );
      return BiometricCapability.none;
    }
  }

  @override
  Future<bool> authenticate({required String reason}) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        // Stated explicitly though it matches the package default: this
        // is security policy, and a future local_auth release changing
        // its default must not silently change SafeKeep's unlock rules.
        // ignore: avoid_redundant_argument_values
        biometricOnly: false,
        // Explicit for the same reason as above.
        // ignore: avoid_redundant_argument_values
        sensitiveTransaction: true,
        // Explicit for the same reason as above.
        // ignore: avoid_redundant_argument_values
        persistAcrossBackgrounding: false,
      );
    } on PlatformException catch (error) {
      // Only the error *code* is logged, never the platform's message —
      // codes are a fixed vocabulary and carry no device or credential
      // detail, whereas messages are free text from the OS.
      AppLogger.instance.warning('Biometric prompt failed: ${error.code}');
      throw BiometricUnavailableException(_messageForCode(error.code));
    }
  }

  /// Turns a `local_auth` error code into something the user can act on.
  ///
  /// An earlier version caught every exception and returned `false`,
  /// which made a genuine misconfiguration indistinguishable from the
  /// user dismissing the prompt: tapping "Unlock with biometrics" simply
  /// did nothing, with the actual cause visible only in a log nobody was
  /// reading. Failing quietly on a security control is the wrong default.
  static String _messageForCode(String code) => switch (code) {
    'NotEnrolled' =>
      'No fingerprint or face is set up on this device. '
          'Add one in your device settings, or unlock with your passphrase.',
    'NotAvailable' || 'no_fragment_activity' =>
      'Biometric unlock is not available on this '
          'device. Use your passphrase instead.',
    'PasscodeNotSet' =>
      'Set a screen lock on your device to use '
          'biometric unlock. Your passphrase still works.',
    'LockedOut' =>
      'Too many failed attempts. Biometric unlock is '
          'temporarily disabled — use your passphrase.',
    'PermanentlyLockedOut' =>
      'Biometric unlock is locked. Unlock your '
          'device with its PIN or password first, then try again.',
    _ => 'Biometric unlock could not start. Use your passphrase instead.',
  };
}
