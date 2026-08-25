import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter/widgets.dart';
import 'package:safekeep/core/config/app_config.dart';
import 'package:safekeep/core/logging/app_logger.dart';

class AppBlocObserver extends BlocObserver {
  const AppBlocObserver();

  // Only the bloc's *type* is logged, never `change`/`transition` — those
  // carry actual state, which for this app will eventually include document
  // metadata. See AppLogger's class-level doc for the full rule.

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    AppLogger.instance.debug('onChange(${bloc.runtimeType})');
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    AppLogger.instance.error(
      'onError(${bloc.runtimeType})',
      error,
      stackTrace,
    );
    super.onError(bloc, error, stackTrace);
  }
}

Future<void> bootstrap(
  AppConfig config,
  FutureOr<Widget> Function() builder,
) async {
  AppLogger.init(config);

  FlutterError.onError = (details) {
    AppLogger.instance.error(
      'Uncaught framework error',
      details.exception,
      details.stack,
    );
  };

  Bloc.observer = const AppBlocObserver();

  // Add cross-flavor configuration here

  runApp(await builder());
}
