import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/api_models.dart';
import '../../models/server_info.dart';
import '../../models/quality_settings.dart';

/// HTTP API client for Ariami server communication
class ApiClient {
  final ServerInfo serverInfo;
  final Duration timeout;

  ApiClient({
    required this.serverInfo,
    this.timeout = const Duration(seconds: 10),
  });

  /// Base URL for API requests
  String get baseUrl => '${serverInfo.baseUrl}/api';

  // ============================================================================
  // CONNECTION ENDPOINTS
  // ============================================================================

  /// Ping server to check connectivity
  Future<Map<String, dynamic>> ping() async {
    final response = await _get('/ping');
    return response;
  }

  /// Connect to server with device information
  Future<ConnectResponse> connect(ConnectRequest request) async {
    final response = await _post('/connect', request.toJson());
    return ConnectResponse.fromJson(response);
  }

  /// Disconnect from server
  Future<DisconnectResponse> disconnect(DisconnectRequest request) async {
    final response = await _post('/disconnect', request.toJson());
    return DisconnectResponse.fromJson(response);
  }

  // ============================================================================
  // LIBRARY ENDPOINTS
  // ============================================================================

  /// Get complete music library
  Future<LibraryResponse> getLibrary() async {
    final response = await _get('/library');
    print('[ApiClient] Library response: $response');
    return LibraryResponse.fromJson(response);
  }

  /// Get all albums
  Future<List<AlbumModel>> getAlbums() async {
    final response = await _get('/albums');
    final albums = (response['albums'] as List<dynamic>? ?? [])
        .map((e) => AlbumModel.fromJson(e as Map<String, dynamic>))
        .toList();
    return albums;
  }

  /// Get album details with songs
  Future<AlbumDetailResponse> getAlbumDetail(String albumId) async {
    final response = await _get('/albums/$albumId');
    return AlbumDetailResponse.fromJson(response);
  }

  /// Get all songs
  Future<List<SongModel>> getSongs() async {
    final response = await _get('/songs');
    final songs = (response['songs'] as List<dynamic>? ?? [])
        .map((e) => SongModel.fromJson(e as Map<String, dynamic>))
        .toList();
    return songs;
  }

  /// Get song details
  Future<SongModel> getSong(String songId) async {
    final response = await _get('/songs/$songId');
    return SongModel.fromJson(response);
  }

  // ============================================================================
  // STREAMING ENDPOINTS
  // ============================================================================

  /// Get stream URL for a song (original quality)
  String getStreamUrl(String songId) {
    return '$baseUrl/stream/$songId';
  }

  /// Get stream URL for a song with specific quality
  ///
  /// [quality] - The streaming quality preset (high, medium, low)
  /// High quality returns original file, medium/low returns transcoded AAC.
  String getStreamUrlWithQuality(String songId, StreamingQuality quality) {
    final baseStreamUrl = '$baseUrl/stream/$songId';

    // High quality doesn't need a parameter (server returns original)
    if (quality == StreamingQuality.high) {
      return baseStreamUrl;
    }

    return '$baseStreamUrl?quality=${quality.toApiParam()}';
  }

  // ============================================================================
  // DOWNLOAD ENDPOINTS
  // ============================================================================

  /// Get download URL for a song (original quality)
  String getDownloadUrl(String songId) {
    return '$baseUrl/download/$songId';
  }

  /// Get download URL for a song with specific quality
  ///
  /// [quality] - The download quality preset (high, medium, low)
  /// High quality returns original file, medium/low returns transcoded AAC.
  String getDownloadUrlWithQuality(String songId, StreamingQuality quality) {
    final baseDownloadUrl = '$baseUrl/download/$songId';

    // High quality doesn't need a parameter (server returns original)
    if (quality == StreamingQuality.high) {
      return baseDownloadUrl;
    }

    return '$baseDownloadUrl?quality=${quality.toApiParam()}';
  }

  // ============================================================================
  // PRIVATE HELPER METHODS
  // ============================================================================

  /// Perform GET request
  Future<Map<String, dynamic>> _get(String endpoint) async {
    try {
      final uri = Uri.parse('$baseUrl$endpoint');
      final response = await http.get(uri).timeout(timeout);

      return _handleResponse(response);
    } catch (e) {
      throw ApiException(
        code: ApiErrorCodes.serverError,
        message: 'Network error: $e',
      );
    }
  }

  /// Perform POST request
  Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    try {
      final uri = Uri.parse('$baseUrl$endpoint');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout);

      return _handleResponse(response);
    } catch (e) {
      throw ApiException(
        code: ApiErrorCodes.serverError,
        message: 'Network error: $e',
      );
    }
  }

  /// Handle HTTP response
  Map<String, dynamic> _handleResponse(http.Response response) {
    // Explicitly decode as UTF-8 to handle non-ASCII characters correctly
    final body = utf8.decode(response.bodyBytes);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      // Success
      return jsonDecode(body) as Map<String, dynamic>;
    } else {
      // Error response
      try {
        final errorJson = jsonDecode(body) as Map<String, dynamic>;
        final errorResponse = ErrorResponse.fromJson(errorJson);
        throw ApiException(
          code: errorResponse.error.code,
          message: errorResponse.error.message,
          details: errorResponse.error.details,
        );
      } catch (e) {
        // Fallback if error parsing fails
        throw ApiException(
          code: ApiErrorCodes.serverError,
          message: 'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        );
      }
    }
  }
}

/// Exception thrown when API call fails
class ApiException implements Exception {
  final String code;
  final String message;
  final Map<String, dynamic>? details;

  ApiException({
    required this.code,
    required this.message,
    this.details,
  });

  @override
  String toString() => 'ApiException($code): $message';

  /// Check if error is a specific type
  bool isCode(String errorCode) => code == errorCode;
}
