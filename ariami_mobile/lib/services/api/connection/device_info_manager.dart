import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Manages device identification information.
///
/// Handles:
/// - Device ID generation and persistence
/// - Device name resolution based on platform
class DeviceInfoManager {
  static const String _deviceIdKey = 'device_id';
  static const Uuid _uuid = Uuid();

  final SharedPreferences? _prefs;

  /// Creates a DeviceInfoManager.
  ///
  /// If [prefs] is provided, it will be used for storage. Otherwise,
  /// [getDeviceId] and [saveDeviceId] will use SharedPreferences.getInstance().
  DeviceInfoManager({SharedPreferences? prefs}) : _prefs = prefs;

  /// Get the unique device ID.
  ///
  /// If an ID exists in SharedPreferences, returns it.
  /// Otherwise, generates a new UUID v4 and saves it.
  ///
  /// Invalid IDs ('unknown-device', empty, or null) will trigger regeneration.
  Future<String> getDeviceId() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(_deviceIdKey);

    if (deviceId == null || deviceId.isEmpty || deviceId == 'unknown-device') {
      deviceId = _uuid.v4();
      await prefs.setString(_deviceIdKey, deviceId);
    }

    return deviceId;
  }

  /// Save a specific device ID.
  ///
  /// This is typically called when the server assigns a device ID.
  Future<void> saveDeviceId(String deviceId) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setString(_deviceIdKey, deviceId);
  }

  /// Get the device name based on the platform.
  ///
  /// Returns:
  /// - 'Android Device' on Android
  /// - 'iOS Device' on iOS
  /// - 'Mobile Device' on other platforms
  Future<String> getDeviceName() async {
    // Get device model/name based on platform
    if (Platform.isAndroid) {
      return 'Android Device';
    } else if (Platform.isIOS) {
      return 'iOS Device';
    } else {
      return 'Mobile Device';
    }
  }

  /// Get the platform identifier string.
  ///
  /// Returns 'android', 'ios', or 'unknown' based on the platform.
  String get platform {
    if (Platform.isAndroid) {
      return 'android';
    } else if (Platform.isIOS) {
      return 'ios';
    } else {
      return 'unknown';
    }
  }
}
