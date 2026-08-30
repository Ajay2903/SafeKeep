# SafeKeep

[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]
[![License: MIT][license_badge]][license_link]

**A privacy-first, offline document vault for Android and iOS.** Scan or
import your passport, licence, insurance and tax documents; they are
encrypted on-device and never leave it in readable form. No server, no
accounts, no telemetry.

> ### 🚧 Status: in active development — Phase 1 of 10 complete
>
> **The encryption layer is built and tested. There is no user interface
> yet.** Running the app today shows the scaffold's placeholder screen.
> The crypto can be exercised through the test suite or a debug harness
> (see [Trying it](#trying-it)).
>
> This repository is deliberately being built bottom-up: the security
> layer first, proven with tests, before any UI is written on top of it.

---

## The idea

Most people keep photos of their passport and insurance papers in their
camera roll or a cloud drive — readable by anything with access to the
account. SafeKeep's premise is that documents like these should be
encrypted with a key only the user holds.

**How it works**

1. On first run the user chooses a passphrase. A 256-bit key is derived
   from it with Argon2id and stored in the device's hardware-backed
   keystore.
2. Documents are scanned or imported, encrypted with AES-256-GCM, and
   written to app-private storage. Metadata (title, category, expiry)
   lives in an encrypted SQLCipher database.
3. Day to day the vault opens with a fingerprint. The passphrase is only
   needed when setting up a new device.
4. Optional backup writes **encrypted blobs** to the user's own Google
   Drive. Even holding those blobs, they are useless without the
   passphrase.

**The deliberate tradeoff:** there is no recovery mechanism. No escrow,
no reset link, no backdoor. If the passphrase is forgotten, the data is
gone. That is what "zero-knowledge" actually costs, and the app is
designed to say so plainly rather than quietly keep a spare key.

---

## Architecture

```
lib/
  security/       ← encryption, key management, biometric gate  (Phase 1 ✅)
  data/           ← encrypted file storage + SQLCipher database (Phase 2)
  domain/         ← models and repository interfaces
  presentation/   ← screens, widgets, BLoC/Cubit state
  core/           ← config, theming, logging, flavor handling   (Phase 0 ✅)
```

`lib/security/` is a **separate top-level module rather than part of the
data layer**, for three reasons:

- **Isolation** — it imports nothing from `data/`, `domain/`, or
  `presentation/`, so the blast radius of a change is contained.
- **Testability** — every platform dependency (keystore, biometrics) sits
  behind a narrow interface, so the entire vault lifecycle is unit-tested
  against fakes with no device required.
- **Auditability** — the whole trust boundary is one directory a reviewer
  can read end to end.

State management is BLoC/Cubit throughout. Three flavors
(development/staging/production) with separate application IDs so they
install side by side.

---

## Security design

Full write-up: [`docs/crypto-design-review.md`](docs/crypto-design-review.md)
— an anonymised, self-contained document prepared for external
cryptographic review.

| | Choice | Why |
|---|---|---|
| **Key derivation** | Argon2id, m=48 MiB, t=2, p=1, 32-byte output | Memory-hard. With no server there is no rate limiting, so an attacker with a stolen backup brute-forces offline without limit — the KDF cost is the only barrier. PBKDF2 parallelises on GPUs at near-zero marginal cost; Argon2id forces 48 MiB per concurrent guess. |
| **Encryption** | AES-256-GCM, fresh 96-bit random nonce per operation | AEAD, so tampering is *detected* rather than decrypted into attacker-influenced plaintext — necessary because blobs are destined for cloud storage someone else may be able to write to. |
| **Key separation** | HKDF-SHA256 with distinct `info` labels | Produces an encryption key and a separate verification value. The verifier can be stored (and travel with a backup) without revealing the encryption key. |
| **Key storage** | Android Keystore / iOS Keychain, biometric-gated | The gate must pass *before* the key is read out of storage. Keychain items are marked device-only so the key never syncs to iCloud. |
| **Blob format** | `[version:1][nonce:12][tag:16][ciphertext:N]` | Fixed 29-byte header; version byte so the format can evolve unambiguously. |
| **Document binding** | Document id bound as GCM associated data | One key encrypts every document, so without this any blob authenticated in any position — an attacker with write access could swap two documents undetected. |

**Storage blob layout**

```
Offset  Length  Field
     0       1  format version
     1      12  nonce (96-bit, fresh CSPRNG per encryption)
    13      16  GCM authentication tag (128-bit)
    29       N  ciphertext
```

The tag additionally covers associated data that is never stored — it is
rebuilt at decryption time from the version byte and the document
identifier, so a blob only authenticates for the document it was written
for.

### Engineering decisions worth calling out

These are the parts I'd most want to talk through in an interview.

**The library was verified before being trusted.** The Argon2id
implementation is pure Dart. Rather than assume it was correct, it is
checked against the **official RFC 9106 §5.3 test vector** as a permanent
test. If that ever fails, every key the app derives is suspect.

**Parameters were measured on real hardware, not extrapolated.** Desktop
benchmarking suggested 64 MiB / t=3 would cost ~300 ms. On a Galaxy A21s
(budget 2020 hardware) it cost **6 seconds** — past Android's ANR
threshold. Argon2id is memory-bandwidth-bound, so it punishes low-end
memory subsystems roughly **19× harder** than a laptop benchmark predicts.
Parameters were re-tuned to 48 MiB / t=2 (~3 s on that device), cutting
iterations rather than memory because memory is what caps an attacker's
parallelism.

**Failure is loud by design.** Tampered ciphertext, corruption, and a
wrong key all raise the same exception — deliberately indistinguishable,
because telling an attacker which occurred leaks information and no
caller can act on the difference. Tests include an exhaustive sweep
flipping *every individual byte* of a blob and asserting each is rejected.

**Writing it down found a bug.** Preparing the review document surfaced a
real gap: because all documents share one key and no associated data was
bound, an attacker with storage write access could swap one valid blob
for another and both would authenticate — the app would show the wrong
document with no error. Fixed by binding the document identity as GCM
associated data, with the format version bumped so the old format is
rejected rather than silently accepted.

---

## Current status

| Phase | Scope | Status |
|---|---|---|
| **0** | Scaffold, flavors, layered structure, CI, theming, logging | ✅ Complete |
| **1** | Crypto core: Argon2id, AES-256-GCM, key lifecycle, biometric gate | ✅ Complete |
| **2** | Encrypted file storage + SQLCipher metadata database | ⏳ Next |
| 3 | Onboarding, lock/unlock screens, auto-lock | Planned |
| 4 | Vault UI — document list, viewer, categories, search | Planned |
| 5 | Document scanner + import | Planned |
| 6 | Expiry reminders via local notifications | Planned |
| 7 | Google Drive backup & multi-device sync | Planned |
| 8 | Audit log, transparency screen, export | Planned |
| 9 | Free/paid tiers, in-app purchase | Planned |
| 10 | Hardening, store submission | Planned |

**Built so far**

- Argon2id key derivation with per-vault salt and persisted cost
  parameters (so tuning them later never orphans an existing vault)
- AES-256-GCM encrypt/decrypt with authenticated failure handling
- Full vault lifecycle: setup → lock → biometric/passphrase unlock →
  crypto-erase, with the key zeroed from memory on lock
- Auto-lock after a background grace period
- Passphrase verification without decrypting any document
- Document-bound ciphertext (GCM associated data) preventing blob
  substitution between documents
- An on-device benchmark and a debug harness for verifying the platform
  integrations that unit tests cannot reach

**Immediately next:** Phase 2 — encrypted file storage on disk and the
SQLCipher metadata database.

### Tests

**117 tests**, `flutter analyze` clean under
[very_good_analysis][very_good_analysis_link].

Line coverage is **94%** for `lib/security` and **92.8%** overall across
code reachable from unit tests. The two platform wrappers — Keystore /
Keychain access and the biometric prompt — are excluded because they
require platform channels that cannot run under `flutter test`. Both are
deliberately kept as thin pass-throughs so that untested code stays
minimal, and they are verified on-device via the debug harness instead.

Coverage includes round-trip correctness at 5 MB, nonce non-reuse across
100 encryptions, wrong-key and tampered-ciphertext rejection, KDF
determinism, locked-vault access denial, and a simulated cross-device
restore that re-derives the key from the passphrase alone.

---

## Trying it

> Requires the Flutter SDK. Android is the current development target.

**Run the test suite** — the meaningful way to see what works today:

```sh
flutter test
```

**Exercise the crypto on a real device.** A throwaway harness that walks
the actual flow — set up vault → encrypt → lock → biometric unlock →
decrypt and verify — against real Keystore and a real fingerprint prompt:

```sh
flutter run --flavor development -d <device-id> -t lib/main_crypto_debug.dart --profile
```

**Benchmark key derivation on your own hardware:**

```sh
flutter test integration_test/crypto_benchmark_test.dart --flavor development -d <device-id>
```

**Run the app itself** (currently the scaffold placeholder — there is no
vault UI yet):

```sh
flutter run --flavor development --target lib/main_development.dart
```

---

## Development

Three flavors, each with its own application ID:

```sh
flutter run --flavor development --target lib/main_development.dart
flutter run --flavor staging     --target lib/main_staging.dart
flutter run --flavor production  --target lib/main_production.dart
```

**Quality gates.** CI runs format-check, `flutter analyze` with
`bloc_lint`, and the full test suite on every push and pull request. A
separate workflow blocks any dependency whose licence falls outside
MIT / BSD-2 / BSD-3 / Apache-2.0. An optional pre-commit hook runs the
same checks locally:

```sh
git config core.hooksPath .githooks
```

**Dependencies are pinned to exact versions** rather than caret ranges,
so builds are reproducible and a transitive update can't silently change
crypto behaviour.

Further reading: [`ARCHITECTURE.md`](ARCHITECTURE.md) for the internal
design notes, [`lib/security/README.md`](lib/security/README.md) for the
security module's rules and layout.

---

## Licence

MIT — see [LICENSE](LICENSE).

[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
