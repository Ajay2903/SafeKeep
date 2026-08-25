# `lib/security/`

This module holds every piece of security-critical code in the app:
encryption, key management, and biometric-gated authentication. It is kept
deliberately separate from `lib/data/` even though the data layer will be
its main caller, for three reasons:

1. **Isolation.** Nothing in here imports `data/`, `domain/`, or
   `presentation/`. It depends only on `core/` (for `AppLogger`, and even
   that only for non-sensitive diagnostic messages) and third-party crypto
   packages. That makes it possible to audit this directory on its own and
   know the blast radius of a change here doesn't cross into feature code.
2. **Testability.** Every capability is defined as an abstract interface
   (`EncryptionService`, `KeyManager`, `BiometricGate`) before it has an
   implementation. Feature code and tests depend on the interface, so real
   crypto can be swapped for a fake in unit tests without touching
   anything outside this directory.
3. **Auditability.** Anyone reviewing the app's security posture should be
   able to read this one directory — interfaces plus their eventual
   implementations — and see the entire trust boundary, rather than
   hunting for encryption calls scattered across the codebase.

## Layout

- `encryption/` — `EncryptionService`: authenticated encryption/decryption
  of bytes. The real implementation (later phase) will use the
  `cryptography` package with AES-GCM.
- `key_management/` — `KeyManager`: generation, retrieval, and deletion of
  the master key. The real implementation (later phase) will use
  `flutter_secure_storage`, which is backed by Android Keystore / iOS
  Keychain.
- `auth/` — `BiometricGate`: biometric/device-credential gate before the
  app unlocks key material. The real implementation (later phase) will use
  `local_auth`.

## Current status (Phase 0)

Everything in this module is an **interface with no implementation** — see
the `TODO(phase-1)` markers on each class. No real cryptography, key
storage, or biometric calls exist yet. That work is explicitly out of
scope for Phase 0, which only establishes the shape of the module.

## Logging rule

Nothing in this module may log key material, derived keys, plaintext, or
passphrases — not even at `debug` level, not even in the development
flavor. See the class-level doc on `AppLogger`
(`lib/core/logging/app_logger.dart`) for the full rule. If a future
implementation needs to log here, log operation names and non-sensitive
identifiers only (e.g. `'key rotated'`, never the key itself).
