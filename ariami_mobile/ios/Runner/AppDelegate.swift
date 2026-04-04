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
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
