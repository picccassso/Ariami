import Flutter
import GoogleCast
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      NativeDownloadBridge.shared.register(messenger: controller.binaryMessenger)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    NativeDownloadBridge.shared.handleEventsForBackgroundURLSession(
      identifier: identifier,
      completionHandler: completionHandler
    )
  }

  override func applicationWillTerminate(_ application: UIApplication) {
    let sessionManager = GCKCastContext.sharedInstance().sessionManager
    if sessionManager.hasConnectedSession() {
      sessionManager.currentCastSession?.remoteMediaClient?.stop()
      sessionManager.endSessionAndStopCasting(true)
    }
    super.applicationWillTerminate(application)
  }
}
