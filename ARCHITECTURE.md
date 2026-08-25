# Safekeep — Architecture (Phase 0)

Safekeep is a privacy-first, offline document vault. This note documents
the foundational setup done before any feature work: flavors, layered
structure, dependencies, theming, logging, and config. Nothing described
below is a feature — screens, models, and real crypto are later phases.

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

**Status:** interfaces only, no implementation. Each carries a
`// TODO(phase1)` marker. Do not instantiate a concrete implementation of
any of them outside tests until that phase.

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
- **Local toolchain:** if `flutter build apk` fails with a Kotlin/Gradle/
  Java version-mismatch error, see the note in the Phase 0 handoff summary
  about the Gradle wrapper and Kotlin version bumps made to unblock this
  on this machine — a different machine's bundled JDK may need the same
  treatment.
