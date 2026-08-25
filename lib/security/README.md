# `lib/security/`

Every piece of security-critical code in the app: key derivation,
encryption, key management, and the biometric gate. Kept separate from
`lib/data/` — even though the data layer is its main caller — for three
reasons:

1. **Isolation.** Nothing here imports `data/`, `domain/`, or
   `presentation/`. It depends only on `core/` (for `AppLogger`, and only
   for non-sensitive diagnostics) and third-party crypto packages. This
   directory can be audited on its own.
2. **Testability.** Every platform-touching dependency sits behind a
   narrow interface (`SecureKeyValueStore`, `BiometricGate`,
   `EncryptionKeySource`), so the full vault lifecycle is exercised in
   unit tests against fakes, with no platform channels.
3. **Auditability.** The whole trust boundary is one directory.

## Layout

```
security/
  security_exceptions.dart        sealed failure hierarchy
  encryption/
    encryption_service.dart       interface (unchanged since Phase 0)
    aes_gcm_encryption_service.dart   AES-256-GCM implementation
    encrypted_blob.dart           stored byte layout + parsing
    encryption_key_source.dart    "give me the key for this id" seam
  key_management/
    key_manager.dart              vault lifecycle interface
    vault_key_manager.dart        implementation
    key_derivation.dart           Argon2id + HKDF
    kdf_parameters.dart           cost factors, persisted per vault
    auto_lock_controller.dart     background grace-period policy
    secure_key_value_store.dart   storage seam
    flutter_secure_storage_store.dart   Keystore/Keychain wrapper
  auth/
    biometric_gate.dart           interface (unchanged since Phase 0)
    local_auth_biometric_gate.dart      local_auth wrapper
```

## Cryptographic design in brief

```text
passphrase + salt
      │  Argon2id (m=48 MiB, t=2, p=1)   ← cost factors persisted per vault
      ▼
  masterKey (32 bytes, never stored)
      │  HKDF-SHA256, two distinct info labels
      ├─────────────────────────► encryptionKey  (AES-256-GCM)
      └─────────────────────────► verifier       (persisted, compared
                                                  in constant time)
```

Stored blob: `[version:1][nonce:12][tag:16][ciphertext:N]`, a fixed
29-byte header. Full rationale for every size is in
`encryption/encrypted_blob.dart`.

Persisted in Keystore/Keychain: salt, KDF parameters, verifier, and the
encryption key. **Never the passphrase, in any form.**

## Rules for anyone working in here

- **Never log key material, plaintext, passphrases, or salts** — not at
  `debug`, not in the development flavor. See `AppLogger`'s class doc. The
  decryption error path is the highest-risk spot; it deliberately logs
  nothing.
- **Never distinguish tampering from a wrong key** in an error surfaced to
  callers. `DecryptionAuthenticationException` covers both on purpose.
- **Never change the HKDF `info` labels, the KDF defaults' meaning, or the
  blob layout** without a migration path. Existing vaults derive with the
  parameters they were created under; changing what is derived orphans
  real user data with no recovery.
- **Never weaken `KdfParameters.current`** without deliberately updating
  the guard test in `test/security/key_management/key_derivation_test.dart`.
- The RFC 9106 conformance test is what justifies trusting the pure-Dart
  Argon2id. Do not delete or skip it.

## Not unit-testable

`FlutterSecureStorageStore` and `LocalAuthBiometricGate` wrap platform
channels and cannot run under `flutter test`. Both are deliberately thin
pass-throughs for that reason — all logic lives in tested code. They need
on-device verification; see the manual checklist in `ARCHITECTURE.md`.
