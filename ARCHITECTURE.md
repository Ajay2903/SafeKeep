# Safekeep — Architecture

Safekeep is a privacy-first, offline document vault.

* **Phase 0** — foundations: flavors, layered structure, dependencies,
  theming, logging, config.
* **Phase 1** — the encryption layer: Argon2id key derivation,
  AES-256-GCM document encryption, and the vault key lifecycle. See
  [Phase 1 — encryption layer](#phase-1--encryption-layer).

No UI feature work has been done yet; screens and data models are later
phases.

## Flavors

Three flavors, each with its own application/bundle ID so they can be
installed side by side on one device:

| Flavor      | Android applicationId              | iOS bundle ID                  | App name       |
|-------------|-------------------------------------|----------------------------------|----------------|
| development | `com.ajaytibrewal.safekeep.dev`     | `com.ajaytibrewal.safekeep.dev`  | `[DEV] Safekeep` |
| staging     | `com.ajaytibrewal.safekeep.stg`     | `com.ajaytibrewal.safekeep.stg`  | `[STG] Safekeep` |
| production  | `com.ajaytibrewal.safekeep`         | `com.ajaytibrewal.safekeep`      | `Safekeep`       |

This was already scaffolded by `very_good_cli` (Android product flavors in
`android/app/build.gradle.kts`, iOS schemes/xcconfigs in
`ios/Runner.xcodeproj`, and `lib/main_development.dart` /
`main_staging.dart` / `main_production.dart` entry points) — Phase 0 only
replaced the placeholder `com.example.verygoodcore.safekeep` ID with a
real one and threaded a flavor-aware `AppConfig` through `bootstrap()`.

Run with, e.g.:

```
flutter run --flavor development -t lib/main_development.dart
```

Build config was verified via `flutter analyze`, `flutter test`, and a
`flutter build apk --flavor <flavor>` dry run for Android; iOS device
builds require Xcode signing, which is a manual step (see the checklist at
the end of this document).

## Layered structure

```
lib/
  app/            very_good_cli's app shell (MaterialApp), now config- and theme-aware
  core/           shared, dependency-light: config, constants, logging, theme
  security/       isolated encryption + key management + biometric auth (interfaces only)
  data/           storage, database, sync — implements domain repositories (empty stubs)
  domain/         plain Dart models + repository interfaces (not created yet — see below)
  presentation/   screens, widgets, blocs/cubits (not created yet — see below)
  counter/        very_good_cli's demo BLoC feature, kept as a live reference example
  l10n/           very_good_cli's localization scaffold
```

Dependency direction: `presentation` → `domain` ← `data` → `security`.
`core` is depended on by everything; nothing depends on `presentation` or
`data` except the app shell.

### Why `security/` is separate from `data/`

Encryption and key management are pulled into their own top-level module
— not folded into `data/` — for three reasons: **isolation** (nothing
outside `security/` reaches into it, and it doesn't import `data/`,
`domain/`, or `presentation/`, so its blast radius is contained and it's
readable as one unit), **testability** (every capability is an abstract
interface — `EncryptionService`, `KeyManager`, `BiometricGate` — so
feature code and tests depend on the interface and can swap in a fake
without touching this directory), and **auditability** (anyone assessing
the app's security posture has exactly one directory to read). See
`lib/security/README.md` for details.

**Status (Phase 1): implemented.** Argon2id key derivation, AES-256-GCM
encryption, the vault key lifecycle, and the biometric gate are all real
code with 92 tests. See the "Phase 1 — encryption layer" section below and
`lib/security/README.md` for the design.

### `data/`, `domain/`, `presentation/`

`data/` has empty stub classes for `AppDatabase` (sqflite_sqlcipher),
`DocumentFileStorage` (path_provider), and `SyncService` (placeholder,
not scheduled). `domain/` and `presentation/` are documented but
intentionally have no `models/`, `repositories/`, `screens/`, or
`widgets/` subdirectories yet — creating them now would mean designing
the vault's data model and screens, which is feature work and out of
scope for Phase 0. Each has a `README.md` explaining what goes there when
the first feature lands.

### Counter feature

`lib/counter/` is very_good_cli's generated example BLoC feature. It's
left in place as a working reference for the project's BLoC/cubit +
`view`/`cubit` split (mirrored by the intended `presentation/screens/`
layout) and is still the app's home screen. It has no relationship to the
document vault and is safe to delete once the first real screen replaces
it as `home:` in `lib/app/view/app.dart`.

## Dependencies added

All pinned to exact versions (no `^` ranges) for reproducible builds.
Versions and licenses below as of 2026-08-25 — re-check before bumping.

| Package | Version | License | Purpose | Maintenance |
|---|---|---|---|---|
| `cryptography` | 2.9.0 | Apache-2.0 | AES-GCM authenticated encryption + key derivation, for the future `EncryptionService` implementation | Verified publisher (dint.dev), 644k weekly downloads, actively maintained |
| `sqflite_sqlcipher` | 3.4.1 | MIT | SQLCipher-encrypted SQLite, for the future `AppDatabase` implementation | Actively maintained, published 20 days before this check |
| `flutter_secure_storage` | 11.0.0 | BSD-3-Clause | Keystore/Keychain-backed secret storage, for the future `KeyManager` implementation | Verified publisher, 3.59M downloads, actively maintained |
| `local_auth` | 3.0.2 | BSD-3-Clause | Biometric/device-credential auth, for the future `BiometricGate` implementation | Verified publisher (flutter.dev), Flutter Favorite-adjacent, actively maintained |
| `flutter_local_notifications` | 22.3.0 | BSD-3-Clause | Local reminders (no push/remote notifications) | Verified publisher, actively maintained |
| `path_provider` | 2.1.6 | BSD-3-Clause | App-private directory paths, for the future `DocumentFileStorage` implementation | Verified publisher (flutter.dev), Flutter Favorite, actively maintained |

All licenses fit the existing `.github/workflows/license_check.yaml`
allowlist (`MIT, BSD-3-Clause, BSD-2-Clause, Apache-2.0`) without
modification.

**Not added yet, on purpose:** Firebase, Google Sign-In, in-app-purchase —
these belong to later phases per the brief.

**Android minSdk:** `flutter_secure_storage` 11.0.0 and
`flutter_local_notifications` 22.3.0 both require API 24+. See the manual
checklist below if you lower `minSdk` later — these packages set the
floor.

### Document scanner (recommended, not integrated)

**`cunning_document_scanner`** (MIT license, v3.0.1) is recommended for
whenever document scanning becomes a feature. It wraps each platform's
native scanner (Android's Google-Play-Services-backed scanner with a
non-Play-Services fallback; iOS's system scanner) rather than shipping a
custom OpenCV-based edge detector, which means less code to audit and
maintain, and a UI users already recognize. It has the strongest
maintenance signal among the Flutter document-scanner packages evaluated
(160 pub points, 265 likes, updated 13 days before this check) compared
to the alternative considered, `flutter_doc_scanner` (MIT, still pre-1.0
at v0.0.21, 140 pub points, 164 likes). Not added to `pubspec.yaml` yet —
this is a recommendation for the phase that builds document capture.

## Theming

`lib/core/theme/`: a single seed color (`AppColors.seed`, a deep muted
blue chosen to read as trustworthy rather than playful) generates
accessible light and dark `ColorScheme`s via Material 3's
`ColorScheme.fromSeed`. `AppTheme.light` / `AppTheme.dark` build the full
`ThemeData` from that scheme and are wired at the `MaterialApp` root in
`lib/app/view/app.dart` — screens should read `Theme.of(context)` rather
than construct their own `ThemeData` or hardcode colors.
`lib/core/constants/app_spacing.dart` provides a 4pt-grid spacing scale
(`xs` through `xxl`) for consistent padding/gaps.

## Logging

`lib/core/logging/app_logger.dart` is the single logging entry point,
backed by `dart:developer`. Its class-level doc states the hard rule
explicitly:

> Never log document contents, decrypted data, passphrases, or key
> material — only identifiers, types, counts, and non-sensitive error
> messages.

This is enforced today, not just documented: `AppBlocObserver` in
`lib/bootstrap.dart` used to log the full `Change`/state object on every
bloc transition (fine for a Counter, dangerous once blocs carry document
data) — it now logs only `bloc.runtimeType`. `AppLogger.init()` is called
once from `bootstrap()` with the running `AppConfig`; in the production
flavor this raises the minimum level to `warning`, so `debug`/`info` never
ship in a production build.

## Config

`lib/core/config/`: `Flavor` (an enum) and `AppConfig` (an immutable
value object: flavor + app name). Each `main_<flavor>.dart` constructs one
`const AppConfig` and passes it through `bootstrap()` into the widget
tree — there's no global mutable singleton to reach for. Add new
per-environment fields (e.g. API base URLs, when sync is designed)
directly to `AppConfig` rather than branching on `Flavor` in feature code.

## Quality gates

- **Linting:** `very_good_analysis` + `bloc_lint/recommended.yaml`
  (already configured in `analysis_options.yaml`). `flutter analyze` is
  clean.
- **CI** (`.github/workflows/main.yaml`, via
  `VeryGoodOpenSource/very_good_workflows`): format check
  (`dart format --set-exit-if-changed`), `flutter analyze` with
  `run_bloc_lint: true`, and `very_good test` with coverage, on every
  push/PR to `main`. `.github/workflows/license_check.yaml` additionally
  blocks any dependency whose license isn't in
  `MIT, BSD-3-Clause, BSD-2-Clause, Apache-2.0`.
- **Pre-commit hook (optional):** `.githooks/pre-commit` runs the same
  three checks (`dart format`, `flutter analyze`, `flutter test`) locally
  before a commit. Not enabled by default. To opt in:

  ```
  git config core.hooksPath .githooks
  ```

  To opt back out: `git config --unset core.hooksPath`.

## Phase 1 — encryption layer

Implemented in `lib/security/`. Design rationale for every parameter lives
next to the code; this is the summary.

### Key derivation: Argon2id

Chosen over PBKDF2-HMAC-SHA256. PBKDF2 parallelises on GPUs and ASICs at
near-zero marginal cost per guess; Argon2id is memory-hard, forcing an
attacker to allocate 48 MiB per concurrent guess. That matters
disproportionately here: SafeKeep is zero-knowledge with no server, so
nothing rate-limits anything. An attacker holding blobs from the user's
own cloud backup cracks offline, unlimited and in parallel. The KDF cost
is the only barrier.

The pure-Dart implementation in `package:cryptography` is verified against
the **official RFC 9106 section 5.3 test vector** by a permanent test.
That test is what justifies trusting it at all.

| Parameter | Value | Why |
|---|---|---|
| memory | 49 152 KiB (48 MiB) | Dominant security factor: memory caps how many guesses an attacker runs *in parallel*. ~2.5x OWASP's 19 MiB floor. Tuned against a real low-end phone (see below). |
| iterations | 2 | OWASP's floor. Passes add only *serial* work, so at a fixed time budget more memory with fewer passes beats the reverse — 48 MiB/t=2 and 32 MiB/t=3 cost the same, but the former keeps half again the memory hardness. |
| parallelism | 1 | Argon2's `p` models *attacker* parallelism, so raising it does not help the defender. OWASP recommends 1. |
| key length | 32 bytes | 256 bits, matching AES-256. |
| salt | 16 bytes, `Random.secure` | RFC 9106 recommendation. Not secret; stored with the vault. Makes rainbow tables useless and stops two users with the same passphrase sharing a key. |

**Cost factors are persisted per vault, not hardcoded.** Argon2id is only
deterministic for fixed parameters, so if a future release raised them and
derivation always used today's values, every existing vault would derive a
different key and its documents would be permanently unreadable.

**These were tuned on real hardware, not extrapolated.** An earlier
64 MiB / t=3 setting measured ~295 ms on an M-series laptop but **6 s on
a Galaxy A21s** (Exynos 850, budget 2020 hardware) — past the 5 s ANR
ceiling and a poor first-run experience. Cutting iterations rather than
memory brought it to a measured **~3 s on that same device**, giving up
as little GPU resistance as possible.

The desktop figure was off by ~20x, far more than a debug-vs-AOT gap
would explain: Argon2id is memory-bandwidth-bound, so it punishes low-end
memory subsystems much harder than a CPU benchmark suggests. Do not tune
these from a laptop.

**Only setup and passphrase unlock pay this cost.** `unlockWithBiometrics`
reads the key straight from Keystore/Keychain and runs no derivation at
all — verified on-device as effectively instant. So the everyday unlock is
unaffected by these values, and a few seconds once at onboarding is a fair
price for the memory hardness.

### Two keys, via HKDF domain separation

```text
masterKey     = Argon2id(passphrase, salt, params)      # never stored
encryptionKey = HKDF-SHA256(masterKey, "safekeep:v1:encryption")
verifier      = HKDF-SHA256(masterKey, "safekeep:v1:verification")
```

Only the verifier is persisted, so domain separation matters: reading it
reveals nothing about the encryption key. Storing the raw master key as
its own verifier would have handed the key over outright. The verifier
still lets an offline attacker *test* guesses — unavoidable for any
offline vault, and precisely what the Argon2id cost defends.

Verifier comparison is constant-time. A short-circuiting compare would
leak, through timing, how many leading bytes matched, letting an attacker
recover it byte-by-byte instead of guessing it whole.

### Encryption: AES-256-GCM

An AEAD mode, so decryption *detects* modification instead of returning
attacker-controlled plaintext. Concretely relevant because blobs are
destined for the user's own cloud storage, where anyone who compromises
that account can modify them. CBC or CTR would decrypt tampered data
silently.

A fresh 96-bit nonce comes from `Random.secure` on every call — never a
counter, since a persisted counter cannot survive reinstalls, crashes, or
device restores, and a repeated GCM nonce under one key leaks the
plaintext XOR and enables forgery.

### Stored blob format

```text
Offset  Length  Field
     0       1  format version (0x01)
     1      12  nonce  (96-bit, fresh per encryption)
    13      16  GCM authentication tag (128-bit)
    29       N  ciphertext (N == plaintext length)
```

Total `29 + N` bytes. 96-bit nonce because GCM consumes that length
directly rather than compressing it through GHASH; full 128-bit tag
because truncation only weakens forgery resistance; version byte so a
future format change is never ambiguous. Random-nonce collisions stay
negligible below ~2^32 encryptions per key, far beyond a personal vault.

### Key lifecycle, end to end

1. **Setup** — user picks a passphrase. A random salt is generated,
   Argon2id derives the master key, HKDF splits it. Salt, KDF parameters,
   verifier, and encryption key go to Keystore/Keychain. The vault is left
   unlocked. The passphrase is never stored.
2. **Use** — `EncryptionService` asks `KeyManager` for the session key via
   `EncryptionKeySource` and encrypts/decrypts documents.
3. **Lock** — explicit, or `AutoLockController` after 30 s in the
   background. The key buffer is zeroed and dropped; `encryptionKeyFor`
   then throws `VaultLockedException`.
4. **Unlock** — either the passphrase (re-derived and verified against the
   verifier) or biometrics/device credential. The gate must succeed
   *before* the key is read out of secure storage.
5. **Delete** — `deleteVault()` removes key, salt, verifier, and
   parameters. A cryptographic erase: every document becomes unrecoverable
   whether or not the ciphertext still exists.

Auto-lock uses a 30-second grace period rather than locking immediately,
because file pickers, camera intents, and share sheets all background the
app during normal use; locking on each would train users to disable it.
`AutoLockController` does not observe `WidgetsBinding` itself — the UI
layer will call `onBackgrounded`/`onForegrounded`, keeping
`lib/security/` free of Flutter UI dependencies and the timing
deterministically testable.

### Deviation from the Phase 0 stubs

`EncryptionService` and `BiometricGate` were implemented **unchanged**.

`KeyManager` was redesigned. Its Phase 0 contract was
`getOrCreateKey(keyId)`, documented as generating a random key on first
use — incompatible with a passphrase-derived zero-knowledge vault: a
random key is not reproducible from the passphrase, so neither "forget it
and the data is gone" nor cross-device restore would hold, and there was
nowhere to express the passphrase, the biometric gate, or the
locked/unlocked state. Silently creating a key on first call would also
mask "no vault exists" as success. `deleteKey`'s crypto-erase intent
survives as `deleteVault()`.

### Known gaps and review notes

* **Dart cannot guarantee erasure of secrets from memory.** Key buffers
  are zeroed on lock, which is real and worth doing, but the GC may have
  copied them already. Passphrases arrive as `String`, which is immutable
  and cannot be wiped at all. This is a language-level limitation.
* **The encryption key is stored at rest** (deliberately, to enable
  biometric unlock). After setup, the passphrase is no longer the only
  thing protecting data *on that device* — hardware-backed storage plus
  the biometric gate are. Blobs backed up elsewhere remain
  passphrase-protected.
* **Cross-device restore is partial.** A restored device can unlock and
  decrypt with the passphrase, but the re-derived key is session-only, so
  biometric unlock will not work there until the vault is explicitly
  adopted on that device. Marked `TODO(phase-backup)`.
* **AES-GCM is pure Dart** (~20 MB/s AOT desktop), so a 10 MB document
  takes a second or two on a phone and blocks the calling isolate.
  `package:cryptography_flutter` swaps in native AES-GCM (~10x) with **no
  change to the blob format**, so it is a drop-in with no data migration.
  Marked `TODO(phase2)`.
* **The platform wrappers are untested by CI.**
  `FlutterSecureStorageStore` and `LocalAuthBiometricGate` need platform
  channels. Both are deliberately thin, but they need on-device
  verification (see checklist).
* **Worth an expert review before Phase 2 builds on this:** the HKDF
  domain-separation scheme, the decision to persist the derived key, and
  the Argon2id cost factors against the low-end-device population you
  actually intend to support.

## Manual follow-ups (not automatable from here)

- **iOS code signing** — set your Team ID / provisioning in Xcode for
  each of the `development`/`staging`/`production` schemes before running
  on a device or archiving.
- **Android signing** — `android/app/build.gradle.kts` reads release
  signing config from `ANDROID_KEYSTORE_*` env vars or a `key.properties`
  file (see the `signingConfigs` block); neither exists yet, needed only
  for release builds.
- **Device/simulator testing** — this phase only verifies build
  config (`flutter analyze`, `flutter test`, `flutter build apk` per
  flavor); running on an actual device or simulator, per the brief, is on
  you.
- **App icons** — `very_good_cli` generated placeholder icons per flavor;
  swap them for real artwork whenever the app's visual identity is ready.
- **On-device crypto benchmark (Phase 1)** — run
  `integration_test/crypto_benchmark_test.dart` on the lowest-end device
  you intend to support:

  ```sh
  flutter devices                        # find the device id
  flutter test integration_test/crypto_benchmark_test.dart \
    --flavor development -d <device-id> --profile
  ```

  Use `--profile`; debug mode is materially slower and will make the
  numbers look worse than a real build. It prints Argon2id timings for
  the production 48 MiB profile alongside 32 MiB and the OWASP floor so
  they can be compared on the same hardware, prints AES-GCM throughput at
  1/5/10 MB, re-checks the RFC 9106 vector on-device, and fails outright
  if derivation crosses the 5 s Android ANR threshold. Guidance for
  reading the result is in the file's doc comment.

  Tune `KdfParameters.current` **before** real vaults exist: each vault
  keeps deriving with the parameters it was created under, so a later
  change only affects new vaults.

- **Other on-device checks (Phase 1)** — unit tests cover everything
  except the two platform wrappers. On a real device, confirm: a vault
  survives an app restart; biometric unlock works and cancelling it
  leaves the vault locked; and the vault key survives an OS update.
- **Android backup exclusion** — confirm the app is excluded from Android
  auto-backup, or that Keystore-held material is not captured by it, so
  vault key material cannot leave the device via a Google account backup.
- **Local toolchain:** if `flutter build apk` fails with a Kotlin/Gradle/
  Java version-mismatch error, see the note in the Phase 0 handoff summary
  about the Gradle wrapper and Kotlin version bumps made to unblock this
  on this machine — a different machine's bundled JDK may need the same
  treatment.
