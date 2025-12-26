import 'dart:convert';
import 'package:http/http.dart' as http;

/// Web service for setup operations
/// Communicates with backend API for music folder configuration and library scanning
class WebSetupService {
  /// Set the music folder path on the server
  ///
  /// Returns true if successful
  Future<bool> setMusicFolder(String path) async {
    try {
      final response = await http.post(
        Uri.parse('/api/setup/music-folder'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'path': path}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['success'] as bool? ?? false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Start the library scan on the server
  ///
  /// Returns true if scan was started successfully
  Future<bool> startScan() async {
    try {
      final response = await http.post(
        Uri.parse('/api/setup/start-scan'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['success'] as bool? ?? false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Get the current scan status
  ///
  /// Returns a map with:
  /// - 'isScanning': bool indicating if scan is in progress
  /// - 'progress': double from 0.0 to 1.0
  /// - 'songsFound': int number of songs found
  /// - 'albumsFound': int number of albums found
  /// - 'currentStatus': String description of current operation
  Future<Map<String, dynamic>> getScanStatus() async {
    try {
      final response = await http.get(
        Uri.parse('/api/setup/scan-status'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return {
          'isScanning': data['isScanning'] ?? false,
          'progress': (data['progress'] as num?)?.toDouble() ?? 0.0,
          'songsFound': data['songsFound'] ?? 0,
          'albumsFound': data['albumsFound'] ?? 0,
          'currentStatus': data['currentStatus'] ?? 'Initializing...',
        };
      }
    } catch (e) {
      // Return default values on error
    }

    return {
      'isScanning': false,
      'progress': 0.0,
      'songsFound': 0,
      'albumsFound': 0,
      'currentStatus': 'Not scanning',
    };
  }

  /// Mark setup as complete on the server
  Future<bool> markSetupComplete() async {
    try {
      final response = await http.post(
        Uri.parse('/api/setup/complete'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['success'] as bool? ?? false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Trigger transition from foreground to background mode
  ///
  /// This causes the foreground server to spawn a background daemon
  /// and then shut down. The browser will briefly disconnect and
  /// automatically reconnect to the new background server.
  ///
  /// Returns a map with:
  /// - 'success': bool indicating if transition was initiated
  /// - 'message': String description
  /// - 'pid': int process ID of background server (on success)
  Future<Map<String, dynamic>> transitionToBackground() async {
    try {
      final response = await http.post(
        Uri.parse('/api/setup/transition-to-background'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'success': false, 'message': 'HTTP ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }
}
