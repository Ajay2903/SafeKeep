import 'dart:convert';
import 'dart:typed_data';

// Types come from sqflite_sqlcipher's re-export of sqflite_common rather
// than importing sqflite_common directly, which is only a transitive
// dependency. They are the same types, so the FFI factory used in tests
// is interchangeable with the SQLCipher one.
import 'package:sqflite_sqlcipher/sqflite.dart' show databaseFactory;
import 'package:sqflite_sqlcipher/sqlite_api.dart';

/// Opens the metadata database.
///
/// This seam exists so the database's SQL is genuinely testable.
/// `sqflite_sqlcipher` runs over a platform channel and cannot execute
/// under `flutter test`; depending on it directly would leave the schema,
/// queries, and migrations untested. Tests substitute an in-memory
/// SQLite factory, so everything above this interface is exercised for
/// real and only encryption-at-rest remains device-verified.
// A one-member interface is intentional: this is a dependency-injection
// seam with two real implementations, not a function in disguise.
// ignore: one_member_abstracts
abstract interface class DatabaseOpener {
  /// Opens (creating if necessary) the database at the configured
  /// location, unlocked with [key].
  Future<Database> open({
    required Uint8List key,
    required int version,
    required OnDatabaseCreateFn onCreate,
    required OnDatabaseVersionChangeFn onUpgrade,
  });
}

/// Production [DatabaseOpener] backed by SQLCipher.
///
/// # How the key is passed
///
/// SQLCipher takes a *passphrase* string, over which it runs its own
/// PBKDF2 (256 000 iterations by default) to produce the actual database
/// key. Our input is already a uniformly random 32-byte HKDF output, so
/// that second KDF adds no security — only a one-off cost when the
/// database is opened, which happens once per unlock.
///
/// The key is base64-encoded rather than passed via SQLCipher's raw-key
/// syntax (`x'<hex>'`, which skips the internal KDF). The raw form would
/// be faster, but how this plugin's native side forwards the string
/// cannot be verified from a unit test, and silently mis-parsing a key
/// format is a bad failure mode: it would produce a *working* database
/// under the wrong key. The safe encoding is used until the raw form can
/// be verified on a device.
// TODO(phase2): measure DB-open latency on-device; if SQLCipher's
// internal PBKDF2 is a noticeable part of unlock, evaluate the raw-key
// syntax and verify byte-for-byte that the derived key matches.
// NOTE: needs on-device verification; SQLCipher cannot run under
// flutter test.
class SqlCipherDatabaseOpener implements DatabaseOpener {
  const SqlCipherDatabaseOpener({required String path}) : this._(path);

  const SqlCipherDatabaseOpener._(this._path);

  final String _path;

  @override
  Future<Database> open({
    required Uint8List key,
    required int version,
    required OnDatabaseCreateFn onCreate,
    required OnDatabaseVersionChangeFn onUpgrade,
  }) {
    return databaseFactory.openDatabase(
      _path,
      options: SqlCipherOpenDatabaseOptions(
        version: version,
        onCreate: onCreate,
        onUpgrade: onUpgrade,
        password: base64Encode(key),
      ),
    );
  }
}
