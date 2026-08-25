import 'package:safekeep/app/app.dart';
import 'package:safekeep/bootstrap.dart';

Future<void> main() async {
  await bootstrap(() => const App());
}
