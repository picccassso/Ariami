import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

class PermissionsService {
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

  Future<PermissionStatus> requestStoragePermission() async {
    if (Platform.isAndroid) {
      if (await _isAndroid13OrHigher()) {
        // Android 13+ uses granular media permissions
        // Request all media permissions at once
        final statuses = await [
          Permission.audio,
          Permission.photos,
          Permission.videos,
        ].request();

        return statuses[Permission.audio] ?? PermissionStatus.denied;
      } else {
        // Android 12 and below use storage permission
        return await Permission.storage.request();
      }
    }
    // iOS doesn't need storage permission (app sandbox)
    return PermissionStatus.granted;
  }

  bool isPermanentlyDenied(PermissionStatus status) {
    return status.isPermanentlyDenied;
  }

  Future<bool> openAppSettings() async {
    return await openAppSettings();
  }

  Future<bool> _isAndroid13OrHigher() async {
    if (!Platform.isAndroid) return false;
    // This is a simplified check - in production you'd check actual SDK version
    return true; // Assume modern Android for now
  }

  bool isStoragePermissionNeeded() {
    return Platform.isAndroid;
  }
}
