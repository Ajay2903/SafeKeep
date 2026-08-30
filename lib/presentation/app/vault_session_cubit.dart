import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:safekeep/core/logging/app_logger.dart';
import 'package:safekeep/data/database/app_database.dart';
import 'package:safekeep/presentation/app/vault_session_state.dart';
import 'package:safekeep/security/auth/biometric_gate.dart';
import 'package:safekeep/security/key_management/auto_lock_controller.dart';
import 'package:safekeep/security/key_management/key_manager.dart';
import 'package:safekeep/security/security_exceptions.dart';

/// Owns the vault's open/closed state for the whole app.
///
/// # What "locking" means here
///
/// Three things have to happen together, which is why they live in one
/// place rather than being called from wherever a lock is triggered:
///
/// 1. key material is cleared from memory,
/// 2. the metadata database is closed, since an open handle keeps
///    decrypted pages in SQLCipher's cache,
/// 3. the state changes, which rebuilds every screen showing decrypted
///    content out of existence.
///
/// A caller doing only the first would leave a screen full of plaintext
/// on display behind a supposedly sealed vault.
///
/// # Logging
///
/// Only lifecycle events. No passphrase, no key, and never a
/// distinguishing detail about *why* an unlock failed.
class VaultSessionCubit extends Cubit<VaultSessionState> {
  VaultSessionCubit({
    required KeyManager keyManager,
    required BiometricGate biometricGate,
    required AppDatabase database,
    Duration? backgroundGracePeriod,
    Duration? inactivityTimeout,
  }) : this._(
         keyManager,
         biometricGate,
         database,
         backgroundGracePeriod ??
             AutoLockController.defaultBackgroundGracePeriod,
         inactivityTimeout ?? AutoLockController.defaultInactivityTimeout,
       );

  VaultSessionCubit._(
    this._keyManager,
    this._biometricGate,
    this._database,
    Duration backgroundGracePeriod,
    Duration inactivityTimeout,
  ) : super(const VaultChecking()) {
    _autoLock = AutoLockController(
      onLock: lock,
      isUnlocked: () => _keyManager.isUnlocked,
      backgroundGracePeriod: backgroundGracePeriod,
      inactivityTimeout: inactivityTimeout,
    );
  }

  final KeyManager _keyManager;
  final BiometricGate _biometricGate;
  final AppDatabase _database;

  late final AutoLockController _autoLock;

  /// Cached so [lock] — which must be synchronous, so decrypted screens
  /// stop rendering in the same frame — can report it without awaiting a
  /// platform call.
  bool _biometricsAvailable = false;

  /// Cached so the synchronous [lock] can label the unlock button
  /// correctly without awaiting the platform gate.
  BiometricCapability _capability = BiometricCapability.none;

  /// Determines what to show on launch.
  Future<void> checkStatus() async {
    final initialized = await _keyManager.isInitialized();
    if (!initialized) {
      _biometricsAvailable = await _biometricGate.isAvailable();
      if (!isClosed) emit(const VaultUninitialized());
      return;
    }
    await _emitLocked();
  }

  /// Creates the vault and opens it.
  ///
  /// The caller is responsible for having confirmed the passphrase and
  /// shown the unrecoverability warning; by the time this runs, those
  /// decisions are made.
  Future<void> createVault(String passphrase) async {
    emit(const VaultSettingUp());
    try {
      await _keyManager.setUpVault(passphrase: passphrase);
      await _openSession();
      AppLogger.instance.info('Vault created and opened');
    } on SecurityException catch (error) {
      AppLogger.instance.error('Vault setup failed: ${error.name}');
      await _emitLocked();
    }
  }

  /// Unlocks with biometrics or the device credential.
  Future<void> unlockWithBiometrics() async {
    final bool unlocked;
    try {
      unlocked = await _keyManager.unlockWithBiometrics();
    } on BiometricUnavailableException catch (error) {
      // Biometrics could not even be attempted. Say why: the user can
      // act on "nothing is enrolled" or "locked out", and silence here
      // is what made this look like a dead button.
      if (!isClosed) await _emitLocked(biometricMessage: error.message);
      return;
    }
    if (isClosed) return;

    if (!unlocked) {
      // A dismissed prompt is not a failed attempt — the user simply
      // closed it, and flagging it as a failure would be alarming.
      await _emitLocked();
      return;
    }
    await _openSession();
  }

  /// Unlocks by passphrase: the fallback when biometrics are
  /// unavailable, not enrolled, or declined.
  Future<void> unlockWithPassphrase(String passphrase) async {
    emit(const VaultUnlocking());

    final unlocked = await _keyManager.unlockWithPassphrase(passphrase);
    if (isClosed) return;

    if (!unlocked) {
      await _emitLocked(lastAttemptFailed: true);
      return;
    }
    await _openSession();
  }

  /// Seals the vault: clears keys, closes the database, and returns the
  /// UI to the locked screen.
  ///
  /// Synchronous on purpose. The state change has to land in the current
  /// frame so screens showing decrypted content stop rendering
  /// immediately; awaiting the database close first would leave them up
  /// for however long that takes.
  ///
  /// Safe to call when already locked, so an auto-lock timer racing an
  /// explicit lock cannot cause trouble.
  void lock() {
    _autoLock.dispose();
    _keyManager.lock();
    if (!isClosed) {
      // Both values come from the cache rather than being re-read:
      // lock() is deliberately synchronous so the key is cleared without
      // awaiting anything, which rules out calling the async gate here.
      emit(
        VaultLocked(
          biometricsAvailable: _biometricsAvailable,
          capability: _capability,
        ),
      );
    }

    // Deliberately not awaited, for the reason above. Failure to close is
    // logged rather than swallowed: the key is already gone, so the data
    // is safe either way, but a persistently failing close is a leak
    // worth knowing about.
    unawaited(
      _database.close().catchError((Object error) {
        AppLogger.instance.warning('Metadata database failed to close');
      }),
    );

    AppLogger.instance.info('Vault locked');
  }

  // ------------------------------------------------------- lifecycle in

  /// Call when the app leaves the foreground.
  void onAppBackgrounded() => _autoLock.onBackgrounded();

  /// Call when the app returns to the foreground.
  void onAppForegrounded() => _autoLock.onForegrounded();

  /// Call on user interaction to defer the idle lock.
  void recordInteraction() => _autoLock.recordInteraction();

  /// Refreshes the cached biometric availability, then emits locked.
  ///
  /// Availability is re-read on every locked transition rather than once
  /// at launch: a user can enrol or remove a fingerprint while the app is
  /// running, and a stale value would either hide the prompt from someone
  /// who just set one up or offer one that no longer works.
  Future<void> _emitLocked({
    bool lastAttemptFailed = false,
    String? biometricMessage,
  }) async {
    _biometricsAvailable = await _biometricGate.isAvailable();
    _capability = await _biometricGate.capability();
    if (isClosed) return;
    emit(
      VaultLocked(
        biometricsAvailable: _biometricsAvailable,
        lastAttemptFailed: lastAttemptFailed,
        biometricMessage: biometricMessage,
        capability: _capability,
      ),
    );
  }

  Future<void> _openSession() async {
    await _database.open(await _keyManager.databaseKey());
    // Cache both while unlocked so the synchronous lock() below has
    // current values to report without awaiting. Availability alone is
    // not enough: without the capability, locking would fall back to a
    // generic "Unlock" label on a device that has a fingerprint.
    _biometricsAvailable = await _biometricGate.isAvailable();
    _capability = await _biometricGate.capability();
    _autoLock.recordInteraction();
    if (!isClosed) emit(const VaultUnlocked());
  }

  @override
  Future<void> close() {
    _autoLock.dispose();
    return super.close();
  }
}
