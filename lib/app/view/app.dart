import 'package:flutter/material.dart';
import 'package:safekeep/core/config/app_config.dart';
import 'package:safekeep/core/theme/app_theme.dart';
import 'package:safekeep/counter/counter.dart';
import 'package:safekeep/l10n/l10n.dart';

class App extends StatelessWidget {
  const App({required this.config, super.key});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: config.appName,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const CounterPage(),
    );
  }
}
