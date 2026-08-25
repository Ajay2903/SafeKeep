# `lib/domain/`

The domain layer: plain Dart, no Flutter and no third-party package
dependencies. This is where business rules and data shapes live,
independent of how they're stored (`lib/data/`) or displayed
(`lib/presentation/`).

## Intended layout (added as features land)

- `models/` — immutable value objects describing app entities (e.g. a
  vault document's metadata). No encryption, no persistence logic — just
  data and validation.
- `repositories/` — abstract interfaces (e.g. `DocumentRepository`) that
  `lib/data/` implements. Blocs/cubits in `lib/presentation/` depend on
  these interfaces, never on `lib/data/` directly, which keeps state
  management testable against fakes.

## Current status (Phase 0)

No models or repository interfaces exist yet — defining them now would
mean designing the document vault's data model, which is feature work and
explicitly out of scope for Phase 0. These subdirectories are created by
the first feature that needs them.
