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

  /// Prompts the user to authenticate.
  ///
  /// Returns `true` only on a successful, fresh authentication — never
  /// cache or bypass this check. Returns `false` when the user dismisses
  /// the prompt, which is a normal action rather than a failure.
  ///
  /// Throws [BiometricUnavailableException] when authentication could not
  /// be attempted at all: nothing enrolled, hardware unavailable, or the
  /// sensor temporarily locked out after repeated failures. These are
  /// distinguished from a dismissal because the user can act on them and
  /// needs to be told, whereas a dismissal was deliberate.
  Future<bool> authenticate({required String reason});
}

/// Biometric authentication could not be attempted.
///
/// Carries a message written for the user, not a platform error string.
class BiometricUnavailableException implements Exception {
  const BiometricUnavailableException(this.message);

  final String message;

  @override
  String toString() => 'BiometricUnavailableException: $message';
}
