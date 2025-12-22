import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    // CRITICAL: Ignore SIGPIPE to prevent crashes when launched from Finder
    // SIGPIPE is sent when writing to a closed pipe/socket, which can happen
    // during Flutter engine initialization when launched without a terminal
    signal(SIGPIPE, SIG_IGN)

    // Set up method channel for dock icon visibility control
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "bma_desktop/dock",
        binaryMessenger: controller.engine.binaryMessenger
      )

      channel.setMethodCallHandler { (call, result) in
        switch call.method {
        case "hideDockIcon":
          NSApp.setActivationPolicy(.accessory)
          result(nil)
        case "showDockIcon":
          NSApp.setActivationPolicy(.regular)
          NSApp.activate(ignoringOtherApps: true)
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // Return false to keep app running when window is hidden to system tray
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
