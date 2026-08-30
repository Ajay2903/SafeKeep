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

## Current status (Phase 2)

Implemented, and composed into a working vault:

- `vault_document_repository.dart` — `VaultDocumentRepository`, the
  `DocumentRepository` implementation. Owns the *ordering* of operations
  across encryption, blob storage, and metadata, which is where a naive
  implementation loses data. Each method documents why its steps run in
  the order they do.
- `document_id.dart` — 128-bit random hex ids. The id is the metadata
  primary key, the blob's filename, *and* the AES-GCM associated data, so
  a collision would be doubly damaging; it is drawn from the platform
  CSPRNG rather than being sequential.
- `storage/document_file_storage.dart` — encrypted blobs on disk, written
  atomically via temp-file-and-rename. Never sees plaintext.
- `storage/vault_directory.dart` — the `path_provider` seam. Device-only.
- `database/app_database.dart` — connection, schema, migrations.
- `database/document_dao.dart` — the only place that knows column names
  and row encoding.
- `database/database_opener.dart` — the SQLCipher seam. Tests substitute
  in-memory SQLite so the SQL is genuinely exercised.
- `data_exceptions.dart` — sealed failure hierarchy for this layer.

`sync/` remains an unscheduled placeholder.

### Why blobs and metadata are stored separately

Document bytes never enter the database, so listing a vault of hundreds
of documents touches no ciphertext and a database dump can never contain
a document. Both halves are encrypted regardless — metadata is sensitive
on its own, since a title alone can say plenty.
