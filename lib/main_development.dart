import 'package:safekeep/app/app.dart';
import 'package:safekeep/bootstrap.dart';
import 'package:safekeep/core/config/app_config.dart';
import 'package:safekeep/core/config/flavor.dart';

Future<void> main() async {
  const config = AppConfig(
    flavor: Flavor.development,
    appName: '[DEV] Safekeep',
  );
  await bootstrap(config, () => const App(config: config));
}
