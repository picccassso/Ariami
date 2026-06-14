import Cocoa
import FlutterMacOS
import ServiceManagement

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Handle the `launch_at_startup` plugin's method channel natively.
    // The Dart `launch_at_startup` package ships no macOS native code, so we
    // implement the channel here using SMAppService (macOS 13+) with a
    // LaunchAgent fallback for older versions. No external SPM dependency.
    FlutterMethodChannel(
      name: "launch_at_startup",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    .setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "launchAtStartupIsEnabled":
        result(LaunchAtStartupHelper.isEnabled())
      case "launchAtStartupSetEnabled":
        if let arguments = call.arguments as? [String: Any],
          let enabled = arguments["setEnabledValue"] as? Bool {
          LaunchAtStartupHelper.setEnabled(enabled)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}

/// Manages launch-at-login for the app.
///
/// Uses SMAppService on macOS 13+ (shown in System Settings > Login Items) and
/// falls back to a per-user LaunchAgent plist on older systems.
enum LaunchAtStartupHelper {
  static func isEnabled() -> Bool {
    if #available(macOS 13.0, *) {
      return SMAppService.mainApp.status == .enabled
    }
    return FileManager.default.fileExists(atPath: legacyAgentPath())
  }

  static func setEnabled(_ enabled: Bool) {
    if #available(macOS 13.0, *) {
      do {
        if enabled {
          if SMAppService.mainApp.status != .enabled {
            try SMAppService.mainApp.register()
          }
        } else {
          if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
          }
        }
      } catch {
        NSLog("[LaunchAtStartup] SMAppService error: \(error)")
      }
      return
    }
    legacySetEnabled(enabled)
  }

  // MARK: - Legacy LaunchAgent fallback (macOS < 13)

  private static let legacyLabel = "com.example.ariamiDesktop.launcher"

  private static func legacyAgentPath() -> String {
    let home = NSHomeDirectory()
    return "\(home)/Library/LaunchAgents/\(legacyLabel).plist"
  }

  private static func legacySetEnabled(_ enabled: Bool) {
    let path = legacyAgentPath()
    if enabled {
      let appBundlePath = Bundle.main.bundlePath
      let plist: [String: Any] = [
        "Label": legacyLabel,
        "ProgramArguments": ["/usr/bin/open", appBundlePath],
        "RunAtLoad": true,
      ]
      do {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
          atPath: dir, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(
          fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: path))
      } catch {
        NSLog("[LaunchAtStartup] Failed to write LaunchAgent: \(error)")
      }
    } else {
      try? FileManager.default.removeItem(atPath: path)
    }
  }
}
