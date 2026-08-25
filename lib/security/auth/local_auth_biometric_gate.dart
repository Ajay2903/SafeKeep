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
/// enrolled credential or locked-out hardware. Those are treated as
/// "authentication did not succeed" (`false`) rather than propagating,
/// because callers cannot act differently on them and a thrown exception
/// on this path risks surfacing platform detail into logs or UI. The
/// failure is logged as a bare event with no error object attached.
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
    } on Exception {
      // No error object is logged: platform exception messages are not
      // worth the risk of leaking device or credential detail into logs.
      AppLogger.instance.warning('Biometric authentication unavailable');
      return false;
    }
  }
}
