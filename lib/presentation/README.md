# `lib/presentation/`

The presentation layer: screens, widgets, and their BLoC/cubit state
management. Depends on `lib/domain/` (repository interfaces, models) and
`lib/core/` (theme, spacing, config), never directly on `lib/data/` or
`lib/security/`.

## Intended layout (added as features land)

- `screens/` — one directory per screen, each following the existing
  `view/` + `cubit/` (or `bloc/`) split already established by
  `lib/counter/` (kept as a working BLoC reference example — safe to
  delete once the first real screen lands).
- `widgets/` — shared widgets reused across more than one screen. A
  widget used by only one screen belongs next to that screen instead.

## Current status (Phase 0)

Empty. The app root (`lib/app/`) already wires up `AppTheme` and
`AppConfig`; the first real screen is feature work for a later phase.
