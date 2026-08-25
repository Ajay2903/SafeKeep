# `lib/data/`

The data layer: everything that reads or writes persistent state. It
implements the abstract repository interfaces defined in `lib/domain/` and
is the only layer allowed to depend on `lib/security/`, third-party
storage/database packages, or the filesystem.

## Layout

- `database/` — encrypted local database access, backed by
  `sqflite_sqlcipher`. The database encryption key comes from
  `security/key_management`, never from a hardcoded value.
- `storage/` — file storage for document blobs on disk (`path_provider`
  for locating app-private directories), plus non-document key/value
  storage (`flutter_secure_storage`) for small secrets.
- `sync/` — placeholder for future optional cloud/remote sync. Local-first
  and fully offline-capable is the default; sync is opt-in and does not
  exist yet.

## Current status (Phase 0)

Every file in this directory is an **empty stub** — a class shape with no
real database, filesystem, or network logic. Concrete implementations land
alongside the first feature that needs them.
