/// Handle to the app's local encrypted database.
///
/// Backed by `sqflite_sqlcipher` in the real implementation: an SQLite
/// database encrypted at rest with a key supplied by
/// `security/key_management`. No tables or queries exist yet — this is a
/// placeholder for the connection lifecycle only.
// TODO(phase1): open a sqflite_sqlcipher database using a key from
// KeyManager; define the schema alongside the first feature that needs it.
abstract interface class AppDatabase {
  Future<void> open();

  Future<void> close();
}
