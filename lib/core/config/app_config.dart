import 'package:safekeep/core/config/flavor.dart';

/// Flavor-aware application configuration.
///
/// This is intentionally a plain, immutable, dependency-free value object.
/// Each `main_<flavor>.dart` entry point constructs exactly one of these and
/// passes it down through `bootstrap` to the widget tree — there is no
/// global mutable singleton to reach for, which keeps configuration
/// testable and explicit.
///
/// Stubbed for Phase 0: no real per-environment secrets or service
/// endpoints yet. Later phases should add fields here (e.g. API base URLs)
/// rather than reading `Flavor` directly in feature code.
class AppConfig {
  const AppConfig({required this.flavor, required this.appName});

  final Flavor flavor;
  final String appName;

  bool get isProduction => flavor == Flavor.production;
  bool get isStaging => flavor == Flavor.staging;
  bool get isDevelopment => flavor == Flavor.development;
}
