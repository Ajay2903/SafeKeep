/// Biometric/device-credential gate that must succeed before key material
/// is unlocked.
///
/// The real implementation (a later phase, not Phase 0) is expected to use
/// `local_auth`, falling back to device passcode/PIN when biometrics
/// aren't enrolled. This interface exists now so that app-unlock flows can
/// be written and tested against it before that implementation lands.
///
/// Until a real implementation lands, do not instantiate a concrete
/// implementation of this interface outside of tests.
// TODO(phase1): implement using local_auth.
abstract interface class BiometricGate {
  /// Whether biometric or device-credential authentication is available on
  /// this device.
  Future<bool> isAvailable();

  /// Prompts the user to authenticate. Returns `true` only on a successful,
  /// fresh authentication — never cache or bypass this check.
  Future<bool> authenticate({required String reason});
}
