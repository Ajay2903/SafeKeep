# `lib/presentation/`

The presentation layer: screens, widgets, and their BLoC/cubit state
management. Depends on `lib/domain/` (repository interfaces, models) and
`lib/core/` (theme, spacing, config), never directly on `lib/data/` or
`lib/security/`.

## Intended layout (added as features land)

- One directory per feature area, each holding its screens and the
  cubit that drives them.
- `widgets/` — shared widgets reused across more than one screen. A
  widget used by only one screen belongs next to that screen instead.

## Current status (Phase 3)

- `app/vault_session_cubit.dart` + `vault_session_state.dart` — the
  top-level lock state machine. Owns what "locking" means: clear keys,
  close the database, change state.
- `app/vault_gate.dart` — selects the screen from that state, and
  observes app lifecycle and pointer events at the root so no screen has
  to opt into auto-lock.
- `onboarding/` — first-run flow: explain, choose a passphrase,
  acknowledge unrecoverability, create.
- `unlock/` — biometric unlock with an always-visible passphrase
  fallback.
- `vault/` — placeholder home behind the lock; replaced in Phase 4.
- `widgets/` — shared pieces: the drawn shield mark, passphrase field and
  strength meter, staggered entrance animation.

### The lock boundary is state, not navigation

Unlocked screens are chosen by `VaultSessionState`, never pushed onto a
navigator. When the vault locks, that subtree is removed from the tree
entirely — its state, controllers, and anything decrypted into memory go
with it. A navigation-based lock depends on every path remembering to
pop, and there is always one that does not.
