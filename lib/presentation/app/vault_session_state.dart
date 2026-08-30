import 'package:meta/meta.dart';

/// The app's top-level state: whether a vault exists, and whether it is
/// open.
///
/// Sealed so the widget tree can switch exhaustively — adding a state
/// later becomes a compile error at every place that renders one, rather
/// than a screen that silently falls through to a default.
///
/// # Why the whole app is driven from this
///
/// Screens showing decrypted content are *rebuilt away* when this leaves
/// [VaultUnlocked], rather than being dismissed by a navigation call.
/// With a navigation-based lock there is always a path that forgets to
/// pop — a deep link, a restored back stack, a race between an auto-lock
/// timer and a push. Making unlocked screens exist only while the state
/// says unlocked removes that class of bug entirely.
@immutable
sealed class VaultSessionState {
  const VaultSessionState();
}

/// Reading whether a vault exists on this device. The first frame.
final class VaultChecking extends VaultSessionState {
  const VaultChecking();
}

/// No vault on this device: show onboarding.
final class VaultUninitialized extends VaultSessionState {
  const VaultUninitialized();
}

/// Creating the vault. Argon2id runs here, taking seconds on a low-end
/// device, so this state exists purely so the UI can say so rather than
/// appearing frozen.
final class VaultSettingUp extends VaultSessionState {
  const VaultSettingUp();
}

/// A vault exists and is sealed.
final class VaultLocked extends VaultSessionState {
  const VaultLocked({
    this.biometricsAvailable = false,
    this.lastAttemptFailed = false,
  });

  /// Whether to offer the biometric prompt at all. False on devices with
  /// nothing enrolled, where the passphrase is the only way in.
  final bool biometricsAvailable;

  /// Whether the previous unlock attempt was rejected.
  ///
  /// Deliberately a flag rather than a message or an attempt counter: the
  /// UI says only that the passphrase was wrong. Reporting *how* wrong,
  /// or how many attempts remain, tells anyone holding the device more
  /// than it tells the owner.
  final bool lastAttemptFailed;

  @override
  bool operator ==(Object other) =>
      other is VaultLocked &&
      other.biometricsAvailable == biometricsAvailable &&
      other.lastAttemptFailed == lastAttemptFailed;

  @override
  int get hashCode => Object.hash(biometricsAvailable, lastAttemptFailed);
}

/// Verifying a passphrase. Argon2id again, hence its own state.
final class VaultUnlocking extends VaultSessionState {
  const VaultUnlocking();
}

/// The vault is open: key material is in memory and the metadata
/// database is connected.
final class VaultUnlocked extends VaultSessionState {
  const VaultUnlocked();
}
