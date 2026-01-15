import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Service for managing system tray functionality.
/// Handles window hide/show behavior and tray menu actions.
class SystemTrayService with TrayListener {
  static final SystemTrayService _instance = SystemTrayService._internal();
  factory SystemTrayService() => _instance;
  SystemTrayService._internal();

  bool _isInitialized = false;
  
  // Method channel for macOS dock icon visibility
  static const _dockChannel = MethodChannel('ariami_desktop/dock');

  /// Initialize the system tray with icon and menu.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Set up the tray icon based on platform
      String iconPath = await _getTrayIconPath();
      
      // Verify the icon file exists
      final iconFile = File(iconPath);
      if (!await iconFile.exists()) {
        print('Warning: Tray icon not found at: $iconPath');
        // Continue without tray icon - app will still work
        _isInitialized = true;
        return;
      }
      
      // On macOS, tray_manager may have issues with certain paths
      // Copy to temp directory as a workaround
      String finalIconPath = iconPath;
      if (Platform.isMacOS && !kDebugMode) {
        try {
          final tempDir = Directory.systemTemp;
          final tempIconFile = File('${tempDir.path}/ariami_tray_icon.png');
          await iconFile.copy(tempIconFile.path);
          finalIconPath = tempIconFile.path;
          print('[Tray] Copied icon to temp: $finalIconPath');
        } catch (e) {
          print('[Tray] Failed to copy icon to temp, using original: $e');
        }
      }
      
      await trayManager.setIcon(finalIconPath);
      
      // Set up the context menu
      Menu menu = Menu(
        items: [
          MenuItem(
            key: 'show_window',
            label: 'Show Ariami',
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'quit',
            label: 'Quit',
          ),
        ],
      );
      
      await trayManager.setContextMenu(menu);
      trayManager.addListener(this);
      
      _isInitialized = true;
    } catch (e) {
      print('Warning: Failed to initialize system tray: $e');
      // Continue without tray - app will still work
      _isInitialized = true;
    }
  }

  /// Get the appropriate tray icon path for the current platform.
  /// Returns absolute path that works in both debug and release modes.
  Future<String> _getTrayIconPath() async {
    // Get the directory containing the executable
    final executableDir = path.dirname(Platform.resolvedExecutable);
    
    if (Platform.isMacOS) {
      if (kDebugMode) {
        // In debug mode, executable is at:
        // /project/build/macos/Build/Products/Debug/app.app/Contents/MacOS/app
        // Navigate up 8 levels from executableDir to get project root
        var projectDir = executableDir;
        for (int i = 0; i < 8; i++) {
          projectDir = path.dirname(projectDir);
        }
        return path.join(projectDir, 'assets', 'Ariami_icon.png');
      }
      // In release mode, the icon is bundled in flutter_assets
      // Use path.normalize to resolve the '..' and get a clean absolute path
      final resourcesDir = path.normalize(path.join(executableDir, '..', 'Frameworks', 'App.framework', 'Resources', 'flutter_assets', 'assets'));
      final iconPath = path.join(resourcesDir, 'Ariami_icon.png');
      // Return normalized path directly - avoid .absolute which can throw
      return path.normalize(iconPath);
    } else if (Platform.isWindows) {
      if (kDebugMode) {
        // In debug mode, executable is at: /project/build/windows/runner/Debug/app.exe
        // Navigate up 4 levels from executableDir to get project root
        var projectDir = executableDir;
        for (int i = 0; i < 4; i++) {
          projectDir = path.dirname(projectDir);
        }
        return path.join(projectDir, 'assets', 'app_icon.ico');
      }
      // In release mode, look for icon in flutter_assets
      return path.join(executableDir, 'data', 'flutter_assets', 'assets', 'app_icon.ico');
    } else if (Platform.isLinux) {
      if (kDebugMode) {
        // In debug mode, executable is at: /project/build/linux/x64/debug/bundle/app
        // Navigate up 5 levels from executableDir to get project root
        var projectDir = executableDir;
        for (int i = 0; i < 5; i++) {
          projectDir = path.dirname(projectDir);
        }
        return path.join(projectDir, 'assets', 'Ariami_icon.png');
      }
      // In release mode, look for icon in flutter_assets
      return path.join(executableDir, 'data', 'flutter_assets', 'assets', 'Ariami_icon.png');
    }
    return '';
  }

  /// Show the main window.
  Future<void> showWindow() async {
    // Show dock icon on macOS
    if (Platform.isMacOS) {
      try {
        await _dockChannel.invokeMethod('showDockIcon');
      } catch (e) {
        print('[Tray] Failed to show dock icon: $e');
      }
    }
    await windowManager.show();
    await windowManager.focus();
  }

  /// Hide the main window to system tray.
  Future<void> hideWindow() async {
    print('[Tray] Hiding window to system tray');
    await windowManager.hide();
    // Hide dock icon on macOS
    if (Platform.isMacOS) {
      try {
        await _dockChannel.invokeMethod('hideDockIcon');
      } catch (e) {
        print('[Tray] Failed to hide dock icon: $e');
      }
    }
  }

  /// Quit the application completely.
  Future<void> quitApp() async {
    trayManager.removeListener(this);
    await trayManager.destroy();
    exit(0);
  }

  /// Handle tray icon click - show the window.
  @override
  void onTrayIconMouseDown() {
    showWindow();
  }

  /// Handle tray icon right click - show context menu.
  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  /// Handle menu item clicks.
  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show_window':
        showWindow();
        break;
      case 'quit':
        quitApp();
        break;
    }
  }

  /// Clean up resources.
  void dispose() {
    trayManager.removeListener(this);
  }
}

