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

  /// What the device will actually prompt with.
  ///
  /// Used only to label the unlock button truthfully. A device with no
  /// fingerprint enrolled still authenticates — via the screen lock — so
  /// calling that button "Unlock with biometrics" tells the user
  /// something false about their own phone.
  Future<BiometricCapability> capability();

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

/// What kind of authentication the device will present.
///
/// Deliberately not a list of every enrolled method: the unlock screen
/// needs one label and one icon, so this reports the single most
/// representative option rather than making the UI choose.
enum BiometricCapability {
  fingerprint,
  face,
  iris,

  /// No biometric is enrolled, but a PIN, pattern, or password is set —
  /// so authentication still works, just not with a body part.
  deviceCredential,

  /// Nothing is available. The passphrase is the only way in.
  none,
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
