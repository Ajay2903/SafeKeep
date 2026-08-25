import 'dart:developer' as developer;

import 'package:safekeep/core/config/app_config.dart';

/// Severity levels, ordered so `index` comparisons work for filtering.
enum LogLevel { debug, info, warning, error }

/// Centralized, flavor-aware logging utility.
///
/// # HARD RULE — read before calling any method on this class
///
/// This logger (and the log output it produces — device logs, crash
/// reports, any future remote log sink) must **never** receive:
///   * document contents, filenames of decrypted documents, or thumbnails
///   * decrypted data of any kind
///   * passphrases, PINs, or biometric material
///   * encryption keys, key material, or key derivation inputs/outputs
///
/// Only log identifiers, types, counts, and non-sensitive error messages —
/// e.g. `AppLogger.instance.info('Document imported')`, never
/// `AppLogger.instance.info('Document imported: $documentText')`.
///
/// This rule applies transitively: if a caught [Object] `error` or
/// [StackTrace] might embed sensitive data (for example an exception
/// message that echoes a decrypted value), sanitize it before passing it to
/// [error] rather than forwarding it verbatim.
///
/// # Flavor behavior
///
/// [init] sets the minimum level from [AppConfig.flavor]: `production`
/// suppresses `debug` and `info` output entirely, so verbose debug logging
/// never ships in a production build.
class AppLogger {
  AppLogger._(this._minLevel);

  static AppLogger _instance = AppLogger._(LogLevel.debug);

  /// The shared logger instance. Call [init] once during bootstrap before
  /// using this; until then it defaults to the most verbose level.
  static AppLogger get instance => _instance;

  /// Configures the shared logger for the running flavor. Call once from
  /// `bootstrap()`.
  static void init(AppConfig config) {
    _instance = AppLogger._(
      config.isProduction ? LogLevel.warning : LogLevel.debug,
    );
  }

  final LogLevel _minLevel;

  void debug(String message) => _log(LogLevel.debug, message);

  void info(String message) => _log(LogLevel.info, message);

  void warning(String message) => _log(LogLevel.warning, message);

  void error(String message, [Object? error, StackTrace? stackTrace]) =>
      _log(LogLevel.error, message, error, stackTrace);

  void _log(
    LogLevel level,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (level.index < _minLevel.index) return;
    developer.log(
      message,
      name: 'safekeep',
      level: _severity(level),
      error: error,
      stackTrace: stackTrace,
    );
  }

  int _severity(LogLevel level) => switch (level) {
    LogLevel.debug => 500,
    LogLevel.info => 800,
    LogLevel.warning => 900,
    LogLevel.error => 1000,
  };
}
