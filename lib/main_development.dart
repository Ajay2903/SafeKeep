import 'package:path_provider/path_provider.dart';
import 'package:safekeep/app/app.dart';
import 'package:safekeep/bootstrap.dart';
import 'package:safekeep/core/config/app_config.dart';
import 'package:safekeep/core/config/flavor.dart';
import 'package:safekeep/data/storage/vault_directory.dart';

Future<void> main() async {
  const config = AppConfig(
    flavor: Flavor.development,
    appName: '[DEV] Safekeep',
  );

  // Resolved here rather than inside the widget tree: path_provider needs
  // a platform channel, and keeping it out of App keeps that widget
  // constructible in a test.
  final documents = await getApplicationDocumentsDirectory();
  final databasePath = '${documents.path}/safekeep.db';
  final blobDirectory = await VaultDirectory.resolve();

  await bootstrap(
    config,
    () => App(
      config: config,
      databasePath: databasePath,
      blobDirectory: blobDirectory,
    ),
  );
}
