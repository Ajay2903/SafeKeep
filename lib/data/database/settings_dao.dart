import 'package:safekeep/data/database/app_database.dart';
import 'package:safekeep/domain/models/reminder_settings.dart';
import 'package:sqflite_sqlcipher/sqlite_api.dart';

/// Reads and writes user preferences.
///
/// A key/value table rather than a column per setting: preferences are
/// added and removed far more often than document fields, and a new one
/// should not require a schema migration every time.
class SettingsDao {
  const SettingsDao({required AppDatabase database}) : this._(database);

  const SettingsDao._(this._database);

  static const String _reminderOffsetsKey = 'reminder_offsets';

  final AppDatabase _database;

  Database get _db => _database.database;

  Future<ReminderSettings> readReminderSettings() async {
    final rows = await _db.query(
      AppDatabase.settingsTable,
      where: 'key = ?',
      whereArgs: [_reminderOffsetsKey],
      limit: 1,
    );
    if (rows.isEmpty) return ReminderSettings.defaults;
    return ReminderSettings.decode(rows.first['value'] as String?);
  }

  Future<void> writeReminderSettings(ReminderSettings settings) async {
    await _db.insert(
      AppDatabase.settingsTable,
      {'key': _reminderOffsetsKey, 'value': settings.encode()},
      // Preferences are overwritten in place; there is only ever one row
      // per key.
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
