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

## Current status (Phase 2)

- `models/document.dart` — `Document`, metadata only. Deliberately never
  carries the document's bytes, so listing a large vault decrypts
  nothing. Its `toString` omits every user-supplied field, since models
  end up in logs.
- `models/document_category.dart` — `DocumentCategory`, persisted by
  stable string rather than enum index so reordering the enum cannot
  re-categorise existing rows.
- `repositories/document_repository.dart` — `DocumentRepository`, the
  vault's public surface. Presentation code depends on this alone and
  never touches the cipher, the filesystem, or SQL.
