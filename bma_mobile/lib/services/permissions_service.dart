import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

class PermissionsService {
  /// Request notification permission
  Future<PermissionStatus> requestNotificationPermission() async {
    if (Platform.isAndroid) {
      // Android 13+ requires notification permission
      return await Permission.notification.request();
    } else if (Platform.isIOS) {
      // iOS always requires notification permission
      return await Permission.notification.request();
    }
    return PermissionStatus.granted;
  }

  /// Request storage permission (Android only)
  Future<PermissionStatus> requestStoragePermission() async {
    if (Platform.isAndroid) {
      // Check Android version and request appropriate permission
      if (await _isAndroid13OrHigher()) {
        // Android 13+ uses granular media permissions
        return await Permission.photos.request();
      } else {
        // Android 12 and below use storage permission
        return await Permission.storage.request();
      }
    }
    // iOS doesn't need storage permission (app sandbox)
    return PermissionStatus.granted;
  }

  /// Check notification permission status
  Future<PermissionStatus> getNotificationPermissionStatus() async {
    return await Permission.notification.status;
  }

  /// Check storage permission status
  Future<PermissionStatus> getStoragePermissionStatus() async {
    if (Platform.isAndroid) {
      if (await _isAndroid13OrHigher()) {
        return await Permission.photos.status;
      } else {
        return await Permission.storage.status;
      }
    }
    return PermissionStatus.granted;
  }

  /// Check if permission is permanently denied
  bool isPermanentlyDenied(PermissionStatus status) {
    return status.isPermanentlyDenied;
  }

  /// Open app settings for re-enabling permissions
  Future<bool> openAppSettings() async {
    return await openAppSettings();
  }

  /// Check if Android 13 or higher
  Future<bool> _isAndroid13OrHigher() async {
    if (!Platform.isAndroid) return false;
    // This is a simplified check - in production you'd check actual SDK version
    return true; // Assume modern Android for now
  }

  /// Check if notification permission is needed for this platform
  bool isNotificationPermissionNeeded() {
    return Platform.isAndroid || Platform.isIOS;
  }

  /// Check if storage permission is needed for this platform
  bool isStoragePermissionNeeded() {
    return Platform.isAndroid;
  }
}
