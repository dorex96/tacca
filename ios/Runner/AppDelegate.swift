import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  /// Ponte della Live Activity: tenuto vivo dall'AppDelegate perché il canale
  /// deve rispondere per tutta la vita dell'app.
  private var liveSession: LiveSessionBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Necessario a flutter_local_notifications per presentare i segnali dei
    // timer anche mentre l'app è in primo piano (§7).
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      liveSession = LiveSessionBridge(messenger: controller.binaryMessenger)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
