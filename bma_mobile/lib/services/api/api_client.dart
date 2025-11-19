import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/api_models.dart';
import '../../models/server_info.dart';

/// HTTP API client for BMA server communication
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

  /// Get stream URL for a song
  String getStreamUrl(String songId) {
    return '$baseUrl/stream/$songId';
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
    if (response.statusCode >= 200 && response.statusCode < 300) {
      // Success
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      // Error response
      try {
        final errorJson = jsonDecode(response.body) as Map<String, dynamic>;
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
