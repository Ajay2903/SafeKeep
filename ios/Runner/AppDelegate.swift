import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  /// Covers the UI while the app is not frontmost.
  ///
  /// iOS has no equivalent of Android's FLAG_SECURE for the app-switcher
  /// snapshot, so the usual approach is to cover the window before iOS
  /// takes its screenshot and uncover once the app is active again.
  private var privacyOverlay: UIView?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // The snapshot is taken after `willResignActive` and before the app is
  // backgrounded, so the overlay must be added here rather than in
  // `didEnterBackground` — by then iOS has already captured the screen.
  override func applicationWillResignActive(_ application: UIApplication) {
    super.applicationWillResignActive(application)
    showPrivacyOverlay()
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    hidePrivacyOverlay()
  }

  private func showPrivacyOverlay() {
    guard privacyOverlay == nil, let window = self.window else { return }

    // A blur rather than a solid fill, so returning to the app reads as
    // the content coming back into focus instead of a flash of blank.
    let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    blur.frame = window.bounds
    blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]

    window.addSubview(blur)
    privacyOverlay = blur
  }

  private func hidePrivacyOverlay() {
    guard let overlay = privacyOverlay else { return }
    privacyOverlay = nil

    UIView.animate(
      withDuration: 0.2,
      animations: { overlay.alpha = 0 },
      completion: { _ in overlay.removeFromSuperview() }
    )
  }
}
