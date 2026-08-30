import 'dart:math';
import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:safekeep/security/auth/biometric_gate.dart';
import 'package:safekeep/security/encryption/aes_gcm_encryption_service.dart';
import 'package:safekeep/security/key_management/key_manager.dart';
import 'package:safekeep/security/security_exceptions.dart';

/// Severity of a line in the debug log.
enum LogTone { info, success, failure }

/// One line of output in the debug harness.
class DebugLine {
  const DebugLine(this.message, this.tone, {this.millis});

  final String message;
  final LogTone tone;

  /// Wall-clock duration of the operation, when it is worth showing.
  final int? millis;
}

class CryptoDebugState {
  const CryptoDebugState({
    this.log = const [],
    this.busy = false,
    this.vaultExists = false,
    this.unlocked = false,
    this.biometricsAvailable = false,
    this.hasEncryptedBlob = false,
  });

  final List<DebugLine> log;
  final bool busy;
  final bool vaultExists;
  final bool unlocked;
  final bool biometricsAvailable;
  final bool hasEncryptedBlob;

  CryptoDebugState copyWith({
    List<DebugLine>? log,
    bool? busy,
    bool? vaultExists,
    bool? unlocked,
    bool? biometricsAvailable,
    bool? hasEncryptedBlob,
  }) {
    return CryptoDebugState(
      log: log ?? this.log,
      busy: busy ?? this.busy,
      vaultExists: vaultExists ?? this.vaultExists,
      unlocked: unlocked ?? this.unlocked,
      biometricsAvailable: biometricsAvailable ?? this.biometricsAvailable,
      hasEncryptedBlob: hasEncryptedBlob ?? this.hasEncryptedBlob,
    );
  }
}

/// Drives the throwaway on-device crypto harness.
///
/// Wired to the **real** `FlutterSecureStorageStore` and
/// `LocalAuthBiometricGate`, which is the entire point: those two are the
/// only parts of the security module that unit tests cannot reach, because
/// they need Keystore/Keychain and a real biometric prompt.
///
/// # Logging discipline
///
/// This harness never prints key material, derived keys, or the
/// passphrase — the same rule that applies everywhere else in the app
/// (see `AppLogger`). It prints ciphertext prefixes (safe by
/// construction), byte lengths, timings, and pass/fail verdicts. The
/// plaintext it shows is synthetic test data generated here, never a real
/// user document.
class CryptoDebugCubit extends Cubit<CryptoDebugState> {
  CryptoDebugCubit({
    required KeyManager keyManager,
    required AesGcmEncryptionService encryption,
    required BiometricGate biometricGate,
  }) : this._(keyManager, encryption, biometricGate);

  CryptoDebugCubit._(
    this._keyManager,
    this._encryption,
    this._biometricGate,
  ) : super(const CryptoDebugState());

  static const String _keyId = 'master';
  static const String _documentId = 'debug-document-1';
  static const String _otherDocumentId = 'debug-document-2';

  final KeyManager _keyManager;
  final AesGcmEncryptionService _encryption;
  final BiometricGate _biometricGate;

  /// The synthetic document most recently encrypted, kept so decryption
  /// can be checked byte-for-byte against it.
  Uint8List? _plaintext;
  Uint8List? _blob;

  void _log(String message, LogTone tone, {int? millis}) {
    emit(
      state.copyWith(
        log: [
          ...state.log,
          DebugLine(message, tone, millis: millis),
        ],
      ),
    );
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (state.busy) return;
    emit(state.copyWith(busy: true));
    try {
      await action();
    } on SecurityException catch (error) {
      _log('${error.name}: ${error.message}', LogTone.failure);
    } on Exception catch (error) {
      // Deliberately broad: this is a diagnostic harness, and an
      // unexpected platform error is exactly what we want to surface.
      _log('Unexpected error: $error', LogTone.failure);
    } finally {
      emit(state.copyWith(busy: false));
      await _refresh();
    }
  }

  Future<void> _refresh() async {
    emit(
      state.copyWith(
        vaultExists: await _keyManager.isInitialized(),
        unlocked: _keyManager.isUnlocked,
        hasEncryptedBlob: _blob != null,
      ),
    );
  }

  /// Reads initial status. Call once when the page mounts.
  Future<void> init() => _guard(() async {
    final available = await _biometricGate.isAvailable();
    emit(state.copyWith(biometricsAvailable: available));
    _log(
      available
          ? 'Biometrics / device credential: AVAILABLE'
          : 'Biometrics / device credential: NOT AVAILABLE',
      available ? LogTone.success : LogTone.failure,
    );
    final exists = await _keyManager.isInitialized();
    _log(
      exists
          ? 'Existing vault found in Keystore/Keychain'
          : 'No vault on this device yet',
      LogTone.info,
    );
  });

  Future<void> setUpVault(String passphrase) => _guard(() async {
    if (passphrase.isEmpty) {
      _log('Enter a passphrase first', LogTone.failure);
      return;
    }
    final stopwatch = Stopwatch()..start();
    await _keyManager.setUpVault(passphrase: passphrase);
    stopwatch.stop();
    _log(
      'Vault created (Argon2id 48 MiB, t=2)',
      LogTone.success,
      millis: stopwatch.elapsedMilliseconds,
    );
    _log(
      'Key written to Keystore/Keychain. Passphrase NOT stored.',
      LogTone.info,
    );
  });

  Future<void> encryptSample() => _guard(() async {
    final plaintext = _syntheticDocument(256 * 1024);
    final stopwatch = Stopwatch()..start();
    final blob = await _encryption.encrypt(
      plaintext,
      keyId: _keyId,
      documentId: _documentId,
    );
    stopwatch.stop();

    _plaintext = plaintext;
    _blob = blob;

    _log(
      'Encrypted ${plaintext.length} bytes -> ${blob.length} bytes '
      '(+${blob.length - plaintext.length} header)',
      LogTone.success,
      millis: stopwatch.elapsedMilliseconds,
    );
    _log('Blob starts: ${_hexPrefix(blob)}', LogTone.info);
    _log(
      'Byte 0 is the format version; next 12 the random nonce.',
      LogTone.info,
    );
  });

  /// Encrypts the same bytes again to show the ciphertext differs.
  Future<void> proveNonceFreshness() => _guard(() async {
    final plaintext = _syntheticDocument(64);
    final first = await _encryption.encrypt(
      plaintext,
      keyId: _keyId,
      documentId: _documentId,
    );
    final second = await _encryption.encrypt(
      plaintext,
      keyId: _keyId,
      documentId: _documentId,
    );

    final identical = _sameBytes(first, second);
    _log('Encrypt #1: ${_hexPrefix(first)}', LogTone.info);
    _log('Encrypt #2: ${_hexPrefix(second)}', LogTone.info);
    _log(
      identical
          ? 'FAIL: identical ciphertext - nonce was reused'
          : 'PASS: same plaintext, different ciphertext (fresh nonce)',
      identical ? LogTone.failure : LogTone.success,
    );
  });

  /// Encrypts under one document id, then tries to read it as another.
  ///
  /// This is the blob-substitution attack: without associated data
  /// binding the document identity, the same vault key made every blob
  /// valid in any position, so a swapped blob decrypted cleanly and the
  /// wrong document was shown with no error.
  Future<void> proveDocumentBinding() => _guard(() async {
    final plaintext = _syntheticDocument(128);
    final blob = await _encryption.encrypt(
      plaintext,
      keyId: _keyId,
      documentId: _documentId,
    );
    _log('Encrypted as "$_documentId"', LogTone.info);

    try {
      await _encryption.decrypt(
        blob,
        keyId: _keyId,
        documentId: _otherDocumentId,
      );
      _log(
        'FAIL: blob decrypted under "$_otherDocumentId" - substitution '
        'is possible',
        LogTone.failure,
      );
    } on DecryptionAuthenticationException {
      _log(
        'PASS: rejected when read as "$_otherDocumentId" - blobs are '
        'bound to their document',
        LogTone.success,
      );
    }

    // And it still decrypts correctly under its own id.
    final ok = await _encryption.decrypt(
      blob,
      keyId: _keyId,
      documentId: _documentId,
    );
    _log(
      _sameBytes(ok, plaintext)
          ? 'PASS: still decrypts correctly under its own id'
          : 'FAIL: no longer decrypts under its own id',
      _sameBytes(ok, plaintext) ? LogTone.success : LogTone.failure,
    );
  });

  Future<void> decryptAndVerify() => _guard(() async {
    final blob = _blob;
    final original = _plaintext;
    if (blob == null || original == null) {
      _log('Encrypt something first', LogTone.failure);
      return;
    }

    final stopwatch = Stopwatch()..start();
    final decrypted = await _encryption.decrypt(
      blob,
      keyId: _keyId,
      documentId: _documentId,
    );
    stopwatch.stop();

    final match = _sameBytes(decrypted, original);
    _log(
      match
          ? 'PASS: decrypted ${decrypted.length} bytes, identical to original'
          : 'FAIL: decrypted bytes do NOT match the original',
      match ? LogTone.success : LogTone.failure,
      millis: stopwatch.elapsedMilliseconds,
    );
  });

  /// Flips one byte of the stored blob and shows decryption refusing it.
  Future<void> tamperAndDecrypt() => _guard(() async {
    final blob = _blob;
    if (blob == null) {
      _log('Encrypt something first', LogTone.failure);
      return;
    }

    final tampered = Uint8List.fromList(blob);
    const index = 100;
    tampered[index] = tampered[index] ^ 0x01;
    _log('Flipped one bit at byte $index of the ciphertext', LogTone.info);

    try {
      await _encryption.decrypt(
        tampered,
        keyId: _keyId,
        documentId: _documentId,
      );
      _log(
        'FAIL: tampered data decrypted without error',
        LogTone.failure,
      );
    } on DecryptionAuthenticationException catch (error) {
      _log('PASS: rejected - ${error.message}', LogTone.success);
    }
  });

  Future<void> lock() => _guard(() async {
    _keyManager.lock();
    _log('Vault locked; key zeroed and dropped from memory', LogTone.info);
  });

  Future<void> unlockWithBiometrics() => _guard(() async {
    _log('Prompting for biometrics / device credential...', LogTone.info);
    final stopwatch = Stopwatch()..start();
    final unlocked = await _keyManager.unlockWithBiometrics();
    stopwatch.stop();
    _log(
      unlocked
          ? 'Unlocked via biometrics'
          : 'Not unlocked (cancelled or failed) - vault stays locked',
      unlocked ? LogTone.success : LogTone.failure,
      millis: stopwatch.elapsedMilliseconds,
    );
  });

  Future<void> unlockWithPassphrase(String passphrase) => _guard(() async {
    final stopwatch = Stopwatch()..start();
    final unlocked = await _keyManager.unlockWithPassphrase(passphrase);
    stopwatch.stop();
    _log(
      unlocked
          ? 'Unlocked via passphrase (key re-derived)'
          : 'Wrong passphrase - vault stays locked',
      unlocked ? LogTone.success : LogTone.failure,
      millis: stopwatch.elapsedMilliseconds,
    );
  });

  Future<void> verifyPassphrase(String passphrase) => _guard(() async {
    final stopwatch = Stopwatch()..start();
    final correct = await _keyManager.verifyPassphrase(passphrase);
    stopwatch.stop();
    _log(
      correct
          ? 'Passphrase correct (checked without unlocking or decrypting)'
          : 'Passphrase incorrect',
      correct ? LogTone.success : LogTone.failure,
      millis: stopwatch.elapsedMilliseconds,
    );
  });

  /// Proves the key is genuinely gone while locked.
  Future<void> tryDecryptWhileLocked() => _guard(() async {
    final blob = _blob;
    if (blob == null) {
      _log('Encrypt something first', LogTone.failure);
      return;
    }
    if (_keyManager.isUnlocked) {
      _log('Lock the vault first', LogTone.failure);
      return;
    }

    try {
      await _encryption.decrypt(
        blob,
        keyId: _keyId,
        documentId: _documentId,
      );
      _log('FAIL: decrypted while locked', LogTone.failure);
    } on VaultLockedException catch (error) {
      _log('PASS: refused - ${error.message}', LogTone.success);
    }
  });

  Future<void> deleteVault() => _guard(() async {
    await _keyManager.deleteVault();
    _blob = null;
    _plaintext = null;
    _log(
      'Vault deleted. Any document encrypted under that key is now '
      'permanently unrecoverable.',
      LogTone.info,
    );
  });

  void clearLog() => emit(state.copyWith(log: const []));

  /// Deterministic synthetic bytes, standing in for a scanned document.
  Uint8List _syntheticDocument(int length) {
    final random = Random(1234);
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }

  String _hexPrefix(Uint8List bytes, {int count = 12}) {
    final take = bytes
        .take(count)
        .map(
          (b) => b.toRadixString(16).padLeft(2, '0'),
        );
    return '${take.join(' ')} ...';
  }

  bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
