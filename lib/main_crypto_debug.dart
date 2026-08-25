import 'package:flutter/material.dart';
import 'package:safekeep/bootstrap.dart';
import 'package:safekeep/core/config/app_config.dart';
import 'package:safekeep/core/config/flavor.dart';
import 'package:safekeep/core/theme/app_theme.dart';
import 'package:safekeep/debug/crypto_debug_page.dart';

/// Throwaway entry point for the on-device crypto harness.
///
/// A separate entry point rather than a route inside the app, for three
/// reasons: the real app stays untouched, it cannot be reached from a
/// shipped build, and removing it later is deleting two files.
///
/// Run it with:
///
/// ```sh
/// flutter run --flavor development -t lib/main_crypto_debug.dart
/// ```
///
/// Pinned to the development flavor deliberately — this writes to and
/// deletes from real Keystore/Keychain storage, and the dev flavor has
/// its own application ID, so it can never touch a production vault.
Future<void> main() async {
  const config = AppConfig(
    flavor: Flavor.development,
    appName: '[DEV] Safekeep crypto debug',
  );
  await bootstrap(config, () => const _CryptoDebugApp());
}

class _CryptoDebugApp extends StatelessWidget {
  const _CryptoDebugApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Safekeep crypto debug',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const CryptoDebugPage(),
    );
  }
}
