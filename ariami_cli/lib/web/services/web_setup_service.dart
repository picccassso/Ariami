import 'package:ariami_core/models/playlist_suggestion.dart';

import '../../models/music_folder_validation_result.dart';
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

  /// Fetch suggested music folder paths with server-side validation.
  Future<List<MusicFolderValidationResult>> getMusicFolderSuggestions() async {
    try {
      final response = await _apiClient.get(
        '/api/setup/music-folder/suggestions',
      );

      if (!response.isSuccess) {
        return const [];
      }

      final data = response.jsonBody ?? <String, dynamic>{};
      final suggestions = data['suggestions'] as List<dynamic>? ?? const [];
      return suggestions
          .whereType<Map<String, dynamic>>()
          .map(MusicFolderValidationResult.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Validate a music folder path without saving it.
  Future<MusicFolderValidationResult> validateMusicFolder(String path) async {
    try {
      final response = await _apiClient.post(
        '/api/setup/music-folder/validate',
        body: <String, dynamic>{'path': path},
      );

      if (response.isSuccess) {
        final data = response.jsonBody ?? <String, dynamic>{};
        return MusicFolderValidationResult.fromJson(data);
      }

      return MusicFolderValidationResult(
        isValid: false,
        path: path,
        error: 'request_failed',
        message: 'Could not validate path (HTTP ${response.statusCode})',
      );
    } catch (e) {
      return MusicFolderValidationResult(
        isValid: false,
        path: path,
        error: 'request_failed',
        message: 'Error validating path: $e',
      );
    }
  }

  /// Set the music folder path on the server
  ///
  /// Returns validation details for success and failure cases.
  Future<MusicFolderValidationResult> setMusicFolder(String path) async {
    try {
      final response = await _apiClient.post(
        '/api/setup/music-folder',
        body: <String, dynamic>{'path': path},
      );

      if (response.isSuccess) {
        final data = response.jsonBody ?? <String, dynamic>{};
        return MusicFolderValidationResult.fromJson(data);
      }

      return MusicFolderValidationResult(
        isValid: false,
        path: path,
        error: 'request_failed',
        message: 'Could not save music folder (HTTP ${response.statusCode})',
      );
    } catch (e) {
      return MusicFolderValidationResult(
        isValid: false,
        path: path,
        error: 'request_failed',
        message: 'Error saving music folder: $e',
      );
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
  /// - 'scannedFileCount': int number of audio files scanned
  /// - 'skippedFileCount': int number of files/directories skipped
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
          'scannedFileCount': data['scannedFileCount'] ?? 0,
          'skippedFileCount': data['skippedFileCount'] ?? 0,
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
      'scannedFileCount': 0,
      'skippedFileCount': 0,
      'currentStatus': 'Not scanning',
    };
  }

  /// Fetch pending playlist-folder suggestions from the last scan.
  ///
  /// Returns an empty list on any failure (the dashboard card just hides).
  Future<List<PlaylistSuggestion>> getPlaylistSuggestions() async {
    try {
      final response = await _apiClient.get('/api/playlists/suggestions');
      if (!response.isSuccess) {
        return const [];
      }

      final data = response.jsonBody ?? <String, dynamic>{};
      final suggestions = data['suggestions'] as List<dynamic>? ?? const [];
      return suggestions
          .whereType<Map<String, dynamic>>()
          .map(PlaylistSuggestion.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Record an import/ignore decision for a suggested playlist folder.
  ///
  /// [decision] is 'import', 'ignore', or 'reset'. Returns true on success;
  /// an import decision also starts a rescan server-side.
  Future<bool> sendPlaylistSuggestionDecision(
    String folderPath,
    String decision,
  ) async {
    try {
      final response = await _apiClient.post(
        '/api/playlists/suggestions/decision',
        body: <String, dynamic>{
          'folderPath': folderPath,
          'decision': decision,
        },
      );
      if (!response.isSuccess) {
        return false;
      }
      final data = response.jsonBody ?? <String, dynamic>{};
      return data['success'] as bool? ?? false;
    } catch (_) {
      return false;
    }
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
  /// and then shut down. The browser may briefly disconnect and
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
