import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/api_models.dart';
import '../../models/auth_models.dart';
import '../../models/server_info.dart';
import '../../models/quality_settings.dart';

/// HTTP API client for Ariami server communication
class ApiClient {
  static const bool _enableV1LibrarySnapshotByDefault = bool.fromEnvironment(
    'ARIAMI_ENABLE_V1_LIBRARY_SNAPSHOT',
    defaultValue: true,
  );
  static const String _v1LibrarySunsetDate = '2026-06-30';

  final ServerInfo serverInfo;
  final Duration timeout;
  final String? deviceId;
  final String? deviceName;
  final bool enableV1LibrarySnapshot;

  /// Session token for authenticated requests (set after login/register)
  String? sessionToken;

  /// Callback invoked when session expires (401 with SESSION_EXPIRED or AUTH_REQUIRED)
  /// Set by ConnectionService to trigger session expiry handling
  void Function()? onSessionExpired;

  ApiClient({
    required this.serverInfo,
    this.timeout = const Duration(seconds: 10),
    this.deviceId,
    this.deviceName,
    this.enableV1LibrarySnapshot = _enableV1LibrarySnapshotByDefault,
    this.sessionToken,
    this.onSessionExpired,
  });

  /// Base URL for API requests
  String get baseUrl => '${serverInfo.baseUrl}/api';

  // ============================================================================
  // CONNECTION ENDPOINTS
  // ============================================================================

  /// Ping server to check connectivity
  Future<Map<String, dynamic>> ping({String? deviceId}) async {
    final endpoint = deviceId == null
        ? '/ping'
        : '/ping?deviceId=${Uri.encodeComponent(deviceId)}';
    final response = await _get(endpoint);
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
  // AUTHENTICATION ENDPOINTS
  // ============================================================================

  /// Register a new user account
  Future<RegisterResponse> register(RegisterRequest request) async {
    final response = await _post('/auth/register', request.toJson());
    return RegisterResponse.fromJson(response);
  }

  /// Login with username and password
  Future<LoginResponse> login(LoginRequest request) async {
    final response = await _post('/auth/login', request.toJson());
    return LoginResponse.fromJson(response);
  }

  /// Logout (invalidate session)
  Future<LogoutResponse> logout(String sessionToken) async {
    final response = await _postWithAuth('/auth/logout', {}, sessionToken);
    return LogoutResponse.fromJson(response);
  }

  /// Get current user info (validates session)
  Future<Map<String, dynamic>> getCurrentUser(String sessionToken) async {
    final response = await _getWithAuth('/me', sessionToken);
    return response;
  }

  // ============================================================================
  // LIBRARY ENDPOINTS
  // ============================================================================

  /// Compatibility-only v1 snapshot endpoint.
  ///
  /// Reserved for legacy clients and CLI web screens when needed.
  /// Primary read paths should use the v2 sync store + local repository.
  /// This method is gated behind `ARIAMI_ENABLE_V1_LIBRARY_SNAPSHOT`.
  Future<LibraryResponse> getLibrary() async {
    if (!enableV1LibrarySnapshot) {
      throw ApiException(
        code: ApiErrorCodes.invalidRequest,
        message: 'Legacy /api/library endpoint is disabled by feature flag. '
            'Use v2 sync store + local repository reads. '
            'Sunset date: $_v1LibrarySunsetDate.',
      );
    }
    print('[ApiClient][WARN] Deprecated /api/library snapshot requested. '
        'Reserved for legacy clients and CLI web screens. '
        'Sunset date: $_v1LibrarySunsetDate.');
    final response = await _get('/library');
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

  /// Get a V2 bootstrap page
  Future<V2BootstrapResponse> getV2BootstrapPage(
      String? cursor, int limit) async {
    final endpoint = _buildEndpointWithQuery(
      '/v2/bootstrap',
      <String, String?>{
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        'limit': '$limit',
      },
    );
    final response = await _get(endpoint);
    return V2BootstrapResponse.fromJson(response);
  }

  /// Get a V2 albums page
  Future<V2AlbumsPageResponse> getV2AlbumsPage(
      String? cursor, int limit) async {
    final endpoint = _buildEndpointWithQuery(
      '/v2/albums',
      <String, String?>{
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        'limit': '$limit',
      },
    );
    final response = await _get(endpoint);
    return V2AlbumsPageResponse.fromJson(response);
  }

  /// Get a V2 songs page
  Future<V2SongsPageResponse> getV2SongsPage(
    String? cursor,
    int limit,
    String? albumId,
  ) async {
    final endpoint = _buildEndpointWithQuery(
      '/v2/songs',
      <String, String?>{
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        'limit': '$limit',
        if (albumId != null && albumId.isNotEmpty) 'albumId': albumId,
      },
    );
    final response = await _get(endpoint);
    return V2SongsPageResponse.fromJson(response);
  }

  /// Get a V2 playlists page
  Future<V2PlaylistsPageResponse> getV2PlaylistsPage(
    String? cursor,
    int limit,
  ) async {
    final endpoint = _buildEndpointWithQuery(
      '/v2/playlists',
      <String, String?>{
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        'limit': '$limit',
      },
    );
    final response = await _get(endpoint);
    return V2PlaylistsPageResponse.fromJson(response);
  }

  /// Get V2 changes since a token
  Future<V2ChangesResponse> getV2Changes(int since, int limit) async {
    final endpoint = _buildEndpointWithQuery(
      '/v2/changes',
      <String, String?>{
        'since': '$since',
        'limit': '$limit',
      },
    );
    final response = await _get(endpoint);
    return V2ChangesResponse.fromJson(response);
  }

  /// Create a server-managed v2 download job.
  Future<DownloadJobCreateResponse> createV2DownloadJob(
    DownloadJobCreateRequest request,
  ) async {
    final response = await _post('/v2/download-jobs', request.toJson());
    return DownloadJobCreateResponse.fromJson(response);
  }

  /// Get v2 download job status.
  Future<DownloadJobStatusResponse> getV2DownloadJobStatus(String jobId) async {
    final encodedJobId = Uri.encodeComponent(jobId);
    final response = await _get('/v2/download-jobs/$encodedJobId');
    return DownloadJobStatusResponse.fromJson(response);
  }

  /// Get paged v2 download job items.
  Future<DownloadJobItemsResponse> getV2DownloadJobItems(
    String jobId, {
    String? cursor,
    int limit = 100,
  }) async {
    final encodedJobId = Uri.encodeComponent(jobId);
    final endpoint = _buildEndpointWithQuery(
      '/v2/download-jobs/$encodedJobId/items',
      <String, String?>{
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        'limit': '$limit',
      },
    );
    final response = await _get(endpoint);
    return DownloadJobItemsResponse.fromJson(response);
  }

  /// Cancel a v2 download job.
  Future<DownloadJobCancelResponse> cancelV2DownloadJob(String jobId) async {
    final encodedJobId = Uri.encodeComponent(jobId);
    final response = await _post('/v2/download-jobs/$encodedJobId/cancel', {});
    return DownloadJobCancelResponse.fromJson(response);
  }

  // ============================================================================
  // STREAMING ENDPOINTS
  // ============================================================================

  /// Request a stream ticket for authenticated streaming
  /// Returns a short-lived token that can be passed as a query parameter
  Future<StreamTicketResponse> getStreamTicket(String songId,
      {String? quality}) async {
    final request = StreamTicketRequest(songId: songId, quality: quality);
    final response = await _post('/stream-ticket', request.toJson());
    return StreamTicketResponse.fromJson(response);
  }

  /// Get stream URL for a song (original quality)
  /// For legacy (non-auth) mode only
  String getStreamUrl(String songId) {
    return '$baseUrl/stream/$songId';
  }

  /// Get stream URL for a song with specific quality
  /// For legacy (non-auth) mode only
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

  /// Get stream URL with stream token for authenticated streaming
  /// The stream token is passed as a query parameter (required for just_audio compatibility)
  String getStreamUrlWithToken(String songId, String streamToken,
      {StreamingQuality? quality}) {
    final params = <String, String>{
      'streamToken': streamToken,
    };

    if (quality != null && quality != StreamingQuality.high) {
      params['quality'] = quality.toApiParam();
    }

    final uri =
        Uri.parse('$baseUrl/stream/$songId').replace(queryParameters: params);
    return uri.toString();
  }

  // ============================================================================
  // DOWNLOAD ENDPOINTS
  // ============================================================================

  /// Get download URL for a song (original quality)
  /// For legacy (non-auth) mode only
  String getDownloadUrl(String songId) {
    return '$baseUrl/download/$songId';
  }

  /// Get download URL for a song with specific quality
  /// For legacy (non-auth) mode only
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

  /// Get download URL with stream token for authenticated downloads
  /// The stream token is passed as a query parameter
  String getDownloadUrlWithToken(String songId, String streamToken,
      {StreamingQuality? quality}) {
    final params = <String, String>{
      'streamToken': streamToken,
    };

    if (quality != null && quality != StreamingQuality.high) {
      params['quality'] = quality.toApiParam();
    }

    final uri =
        Uri.parse('$baseUrl/download/$songId').replace(queryParameters: params);
    return uri.toString();
  }

  // ============================================================================
  // PRIVATE HELPER METHODS
  // ============================================================================

  /// Perform GET request (includes Authorization header if sessionToken is set)
  Future<Map<String, dynamic>> _get(String endpoint) async {
    try {
      final uri = _withDeviceParams(Uri.parse('$baseUrl$endpoint'));
      final headers = <String, String>{};
      if (sessionToken != null) {
        headers['Authorization'] = 'Bearer $sessionToken';
      }
      final response = await http.get(uri, headers: headers).timeout(timeout);

      return _handleResponse(response);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        code: ApiErrorCodes.serverError,
        message: 'Network error: $e',
      );
    }
  }

  /// Perform POST request (includes Authorization header if sessionToken is set)
  Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    try {
      final uri = _withDeviceParams(Uri.parse('$baseUrl$endpoint'));
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (sessionToken != null) {
        headers['Authorization'] = 'Bearer $sessionToken';
      }
      final response = await http
          .post(
            uri,
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(timeout);

      return _handleResponse(response);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        code: ApiErrorCodes.serverError,
        message: 'Network error: $e',
      );
    }
  }

  /// Perform GET request with Authorization header
  Future<Map<String, dynamic>> _getWithAuth(
    String endpoint,
    String sessionToken,
  ) async {
    try {
      final uri = _withDeviceParams(Uri.parse('$baseUrl$endpoint'));
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $sessionToken'},
      ).timeout(timeout);

      return _handleResponse(response);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        code: ApiErrorCodes.serverError,
        message: 'Network error: $e',
      );
    }
  }

  /// Perform POST request with Authorization header
  Future<Map<String, dynamic>> _postWithAuth(
    String endpoint,
    Map<String, dynamic> body,
    String sessionToken,
  ) async {
    try {
      final uri = _withDeviceParams(Uri.parse('$baseUrl$endpoint'));
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $sessionToken',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);

      return _handleResponse(response);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        code: ApiErrorCodes.serverError,
        message: 'Network error: $e',
      );
    }
  }

  Uri _withDeviceParams(Uri uri) {
    if (deviceId == null || deviceId!.isEmpty) {
      return uri;
    }

    final params = Map<String, String>.from(uri.queryParameters);
    params['deviceId'] = deviceId!;
    if (deviceName != null && deviceName!.isNotEmpty) {
      params['deviceName'] = deviceName!;
    }

    return uri.replace(queryParameters: params);
  }

  String _buildEndpointWithQuery(
    String endpoint,
    Map<String, String?> queryParameters,
  ) {
    final filtered = <String, String>{
      for (final entry in queryParameters.entries)
        if (entry.value != null) entry.key: entry.value!,
    };
    if (filtered.isEmpty) return endpoint;
    final query = Uri(queryParameters: filtered).query;
    return '$endpoint?$query';
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

        // Check for session expiry errors and notify callback
        if (response.statusCode == 401 &&
            (errorResponse.error.code == ApiErrorCodes.sessionExpired ||
                errorResponse.error.code == ApiErrorCodes.authRequired)) {
          // Notify session expired (if callback is set and we had a session)
          if (onSessionExpired != null && sessionToken != null) {
            onSessionExpired!();
          }
        }

        throw ApiException(
          code: errorResponse.error.code,
          message: errorResponse.error.message,
          details: errorResponse.error.details,
        );
      } catch (e) {
        // Re-throw if it's already an ApiException
        if (e is ApiException) rethrow;

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
