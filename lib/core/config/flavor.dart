/// The build flavor the app was compiled with.
///
/// One of these is selected at compile time by the flavor-specific entry
/// point (`main_development.dart`, `main_staging.dart`,
/// `main_production.dart`) and threaded through `AppConfig` to the rest of
/// the app.
enum Flavor {
  development,
  staging,
  production;

  bool get isProduction => this == Flavor.production;
}
