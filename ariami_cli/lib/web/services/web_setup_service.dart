import 'web_api_client.dart';
import 'web_auth_service.dart';

/// Web service for setup operations
/// Communicates with backend API for music folder configuration and library scanning
class WebSetupService {
  WebSetupService()
      : _apiClient = WebApiClient(
          tokenProvider: _authService.getSessionToken,
        );

  static final WebAuthService _authService = WebAuthService();
  final WebApiClient _apiClient;

  /// Set the music folder path on the server
  ///
  /// Returns true if successful
  Future<bool> setMusicFolder(String path) async {
    try {
      final response = await _apiClient.post(
        '/api/setup/music-folder',
        body: <String, dynamic>{'path': path},
      );

      if (response.isSuccess) {
        final data = response.jsonBody ?? <String, dynamic>{};
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
      final response = await _apiClient.post(
        '/api/setup/start-scan',
      );

      if (response.isSuccess) {
        final data = response.jsonBody ?? <String, dynamic>{};
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
      final response = await _apiClient.get(
        '/api/setup/scan-status',
      );

      if (response.isSuccess) {
        final data = response.jsonBody ?? <String, dynamic>{};
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
      final response = await _apiClient.post(
        '/api/setup/complete',
      );

      if (response.isSuccess) {
        final data = response.jsonBody ?? <String, dynamic>{};
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
      final response = await _apiClient.post(
        '/api/setup/transition-to-background',
      );

      if (response.isSuccess) {
        return response.jsonBody ?? <String, dynamic>{};
      }
      return {'success': false, 'message': 'HTTP ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }
}
