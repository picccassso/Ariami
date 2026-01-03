import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // Activity token to prevent App Nap when server is running
  private var backgroundActivity: NSObjectProtocol?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // CRITICAL: Ignore SIGPIPE to prevent crashes when launched from Finder
    // SIGPIPE is sent when writing to a closed pipe/socket, which can happen
    // during Flutter engine initialization when launched without a terminal
    signal(SIGPIPE, SIG_IGN)

    // Set up method channel for dock icon visibility control
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "ariami_desktop/dock",
        binaryMessenger: controller.engine.binaryMessenger
      )

      channel.setMethodCallHandler { [weak self] (call, result) in
        switch call.method {
        case "hideDockIcon":
          NSApp.setActivationPolicy(.accessory)
          result(nil)
        case "showDockIcon":
          NSApp.setActivationPolicy(.regular)
          NSApp.activate(ignoringOtherApps: true)
          result(nil)
        case "preventAppNap":
          self?.preventAppNap()
          result(nil)
        case "allowAppNap":
          self?.allowAppNap()
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  /// Prevent macOS from putting the app into App Nap mode
  /// This keeps the HTTP server responsive when the window is minimized
  private func preventAppNap() {
    // Only create one activity at a time
    guard backgroundActivity == nil else {
      print("[AppDelegate] App Nap prevention already active")
      return
    }

    // Begin background activity with high priority
    // UserInitiated: Indicates the task is important and user-facing
    // IdleSystemSleepDisabled: Prevents system sleep while app is idle
    backgroundActivity = ProcessInfo.processInfo.beginActivity(
      options: [.userInitiated, .idleSystemSleepDisabled],
      reason: "Running music streaming server"
    )
    print("[AppDelegate] App Nap prevention enabled - server will stay responsive when minimized")
  }

  /// Allow macOS to put the app into App Nap mode
  /// Call this when the server is stopped
  private func allowAppNap() {
    if let activity = backgroundActivity {
      ProcessInfo.processInfo.endActivity(activity)
      backgroundActivity = nil
      print("[AppDelegate] App Nap prevention disabled")
    }
  }

  override func applicationWillTerminate(_ notification: Notification) {
    // Clean up background activity on quit
    allowAppNap()
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // Return false to keep app running when window is hidden to system tray
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
