import 'package:ariami_core/models/music_availability.dart';
import 'package:ariami_core/models/lyrics_models.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:ariami_core/services/recommendations/music_discovery_api_key_config.dart';
import 'package:http/http.dart' as http;
import '../../models/api_models.dart';
import '../../models/auth_models.dart';
import '../../models/server_info.dart';
import '../../models/quality_settings.dart';

class ApiClient {
  MusicAvailability musicAvailability = MusicAvailability.unknown;
  void Function(MusicAvailability)? onMusicAvailabilityChanged;

  final ServerInfo serverInfo;
  final Duration timeout;
  final String? deviceId;
  final String? deviceName;
  final http.Client _client;

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
    this.sessionToken,
    this.onSessionExpired,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Release pooled sockets when this endpoint is replaced or disconnected.
  void close() {
    onMusicAvailabilityChanged = null;
    _client.close();
  }

  String get baseUrl => '${serverInfo.baseUrl}/api';

  Future<Map<String, dynamic>> ping({String? deviceId}) async {
    final endpoint = deviceId == null
        ? '/ping'
        : '/ping?deviceId=${Uri.encodeComponent(deviceId)}';
    final response = await _get(endpoint);
    musicAvailability =
        MusicAvailability.fromJson(response['musicAvailability']);
    onMusicAvailabilityChanged?.call(musicAvailability);
    return response;
  }

  Future<ConnectResponse> connect(ConnectRequest request) async {
    final response = await _post('/connect', request.toJson());
    return ConnectResponse.fromJson(response);
  }

  Future<DisconnectResponse> disconnect(DisconnectRequest request) async {
    final response = await _post('/disconnect', request.toJson());
    return DisconnectResponse.fromJson(response);
  }

  /// Update display aliases for LAN and Tailscale endpoints (Admin only).
  Future<Map<String, dynamic>> updateEndpointAliases({
    String? lanAlias,
    String? tailscaleAlias,
  }) async {
    final payload = <String, dynamic>{
      'lanAlias': lanAlias,
      'tailscaleAlias': tailscaleAlias,
    };
    if (sessionToken != null && sessionToken!.isNotEmpty) {
      return _postWithAuth('/server-info/aliases', payload, sessionToken!);
    }
    return _post('/server-info/aliases', payload);
  }

  Future<RegisterResponse> register(RegisterRequest request) async {
    final response = await _post('/auth/register', request.toJson());
    return RegisterResponse.fromJson(response);
  }

  Future<LoginResponse> login(LoginRequest request) async {
    final response = await _post('/auth/login', request.toJson());
    return LoginResponse.fromJson(response);
  }

  Future<LogoutResponse> logout(String sessionToken) async {
    final response = await _postWithAuth('/auth/logout', {}, sessionToken);
    return LogoutResponse.fromJson(response);
  }

  Future<Map<String, dynamic>> getCurrentUser(String sessionToken) async {
    final response = await _getWithAuth('/me', sessionToken);
    return response;
  }

  /// Fetches lyrics for the given [songId], or null if unavailable.
  Future<SongLyrics?> getLyrics(String songId) async {
    try {
      final response = await _get('/lyrics/${Uri.encodeComponent(songId)}');
      return SongLyrics.fromJson(response);
    } catch (_) {
      return null;
    }
  }

  /// Fetch the current user's avatar bytes, or null if no avatar is set.
  Future<Uint8List?> getCurrentUserAvatar(String sessionToken) async {
    try {
      final uri = _withDeviceParams(Uri.parse('$baseUrl/me/avatar'));
      final response = await _client.get(
        uri,
        headers: {'Authorization': 'Bearer $sessionToken'},
      ).timeout(timeout);

      if (response.statusCode == 404) return null;
      _throwIfByteResponseFailed(response);
      return response.bodyBytes;
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        code: ApiErrorCodes.serverError,
        message: 'Network error: $e',
      );
    }
  }

  Future<Map<String, dynamic>> uploadCurrentUserAvatar(
    String sessionToken, {
    required Uint8List bytes,
    required String contentType,
  }) async {
    try {
      final uri = _withDeviceParams(Uri.parse('$baseUrl/me/avatar'));
      final response = await http
          .put(
            uri,
            headers: {
              'Authorization': 'Bearer $sessionToken',
              'Content-Type': contentType,
            },
            body: bytes,
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

  Future<void> deleteCurrentUserAvatar(String sessionToken) async {
    try {
      final uri = _withDeviceParams(Uri.parse('$baseUrl/me/avatar'));
      final response = await _client.delete(
        uri,
        headers: {'Authorization': 'Bearer $sessionToken'},
      ).timeout(timeout);

      _throwIfByteResponseFailed(response);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        code: ApiErrorCodes.serverError,
        message: 'Network error: $e',
      );
    }
  }

  Future<ServerInfo> getServerInfo() async {
    final response = await _get('/server-info');
    return ServerInfo.fromJson(response);
  }

  Future<List<AlbumModel>> getAlbums() async {
    final response = await _get('/albums');
    final albums = (response['albums'] as List<dynamic>? ?? [])
        .map((e) => AlbumModel.fromJson(e as Map<String, dynamic>))
        .toList();
    return albums;
  }

  Future<AlbumDetailResponse> getAlbumDetail(String albumId) async {
    final response = await _get('/albums/$albumId');
    return AlbumDetailResponse.fromJson(response);
  }

  Future<List<SongModel>> getSongs() async {
    final response = await _get('/songs');
    final songs = (response['songs'] as List<dynamic>? ?? [])
        .map((e) => SongModel.fromJson(e as Map<String, dynamic>))
        .toList();
    return songs;
  }

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

  Future<DownloadJobCreateResponse> createV2DownloadJob(
    DownloadJobCreateRequest request,
  ) async {
    final response = await _post('/v2/download-jobs', request.toJson());
    return DownloadJobCreateResponse.fromJson(response);
  }

  Future<DownloadJobStatusResponse> getV2DownloadJobStatus(String jobId) async {
    final encodedJobId = Uri.encodeComponent(jobId);
    final response = await _get('/v2/download-jobs/$encodedJobId');
    return DownloadJobStatusResponse.fromJson(response);
  }

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

  Future<DownloadJobCancelResponse> cancelV2DownloadJob(String jobId) async {
    final encodedJobId = Uri.encodeComponent(jobId);
    final response = await _post('/v2/download-jobs/$encodedJobId/cancel', {});
    return DownloadJobCancelResponse.fromJson(response);
  }

  /// Upload a batch of listening events (idempotent by eventId).
  Future<Map<String, dynamic>> postListeningEvents(
    List<Map<String, dynamic>> events,
  ) async {
    return _post('/v2/listening/events', {'events': events});
  }

  Future<Map<String, dynamic>> getListeningSummary() async {
    return _get('/v2/listening/summary');
  }

  /// Fetch totals plus top songs / credited artists / albums for one local
  /// day (`yyyy-mm-dd`). A [limit] of 0 requests every ranked entry
  /// (older servers reject 0). Requires a server with the stats
  /// derivation layer; older servers respond 404 and callers must degrade
  /// gracefully.
  Future<Map<String, dynamic>> getListeningDay(
    String date, {
    int limit = 50,
  }) async {
    final endpoint = _buildEndpointWithQuery(
      '/v2/listening/day',
      <String, String?>{'date': date, 'limit': '$limit'},
    );
    return _get(endpoint);
  }

  /// Fetch totals, per-day breakdown and top songs / credited artists /
  /// albums for an inclusive local-day range (`yyyy-mm-dd`).
  Future<Map<String, dynamic>> getListeningPeriod({
    required String from,
    required String to,
    int limit = 50,
  }) async {
    final endpoint = _buildEndpointWithQuery(
      '/v2/listening/period',
      <String, String?>{'from': from, 'to': to, 'limit': '$limit'},
    );
    return _get(endpoint);
  }

  /// Fetch top credited artists (multi-artist strings split server-side),
  /// all-time when [days] is null. A [limit] of 0 requests every artist
  /// (older servers reject 0).
  Future<Map<String, dynamic>> getListeningArtists({
    int? days,
    int limit = 50,
  }) async {
    final endpoint = _buildEndpointWithQuery(
      '/v2/listening/artists',
      <String, String?>{if (days != null) 'days': '$days', 'limit': '$limit'},
    );
    return _get(endpoint);
  }

  Future<Map<String, dynamic>> postListeningReset() async {
    return _post('/v2/listening/reset', {});
  }

  Future<List<Map<String, dynamic>>> getPins() async {
    final response = await _get('/pins');
    return (response['pins'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<void> pinItem(String type, String targetId) async {
    await _post('/pins', <String, dynamic>{
      'type': type,
      'targetId': targetId,
    });
  }

  Future<void> unpinItem(String type, String targetId) async {
    await _delete(
      '/pins/${Uri.encodeComponent(type)}/${Uri.encodeComponent(targetId)}',
    );
  }

  Future<List<Map<String, dynamic>>> importPins(
    List<dynamic> pins, {
    required bool replace,
  }) async {
    final response = await _post('/pins/import', <String, dynamic>{
      'pins': pins,
      'replace': replace,
    });
    return (response['pins'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  /// Fetch playlist edits together with the custom cover-image manifest the
  /// server returns on the same endpoint.
  Future<
      ({
        List<Map<String, dynamic>> edits,
        List<Map<String, dynamic>> images
      })> getPlaylistEditsAndImages() async {
    final response = await _get('/playlists/edits');
    return (
      edits: _mapList(response['edits']),
      images: _mapList(response['images']),
    );
  }

  List<Map<String, dynamic>> _mapList(dynamic value) =>
      (value as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);

  Future<void> putPlaylistEdit(
    String playlistId, {
    required List<String> songIds,
    String? name,
    required List<String> baseSnapshot,
  }) async {
    await _put(
      '/playlists/${Uri.encodeComponent(playlistId)}/edit',
      <String, dynamic>{
        'songIds': songIds,
        'name': name,
        'baseSnapshot': baseSnapshot,
      },
    );
  }

  Future<void> deletePlaylistEdit(String playlistId) async {
    await _delete('/playlists/${Uri.encodeComponent(playlistId)}/edit');
  }

  /// Upload/replace a playlist's custom cover image. Returns the server's new
  /// image version (updatedAt milliseconds), or null if the response omitted
  /// it.
  Future<int?> putPlaylistImage(
    String playlistId, {
    required Uint8List bytes,
    required String contentType,
  }) async {
    try {
      final uri = _withDeviceParams(Uri.parse(
        '$baseUrl/playlists/${Uri.encodeComponent(playlistId)}/image',
      ));
      final headers = <String, String>{'Content-Type': contentType};
      if (sessionToken != null) {
        headers['Authorization'] = 'Bearer $sessionToken';
      }
      final response = await _client
          .put(uri, headers: headers, body: bytes)
          .timeout(timeout);
      final json = _handleResponse(response);
      final image = json['image'];
      if (image is! Map) return null;
      return (image['updatedAt'] as num?)?.toInt();
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        code: ApiErrorCodes.serverError,
        message: 'Network error: $e',
      );
    }
  }

  Future<Uint8List?> getPlaylistImage(String playlistId) async {
    try {
      final uri = _withDeviceParams(Uri.parse(
        '$baseUrl/playlists/${Uri.encodeComponent(playlistId)}/image',
      ));
      final headers = <String, String>{};
      if (sessionToken != null) {
        headers['Authorization'] = 'Bearer $sessionToken';
      }
      final response =
          await _client.get(uri, headers: headers).timeout(timeout);
      if (response.statusCode == 404) return null;
      _throwIfByteResponseFailed(response);
      return response.bodyBytes;
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        code: ApiErrorCodes.serverError,
        message: 'Network error: $e',
      );
    }
  }

  Future<void> deletePlaylistImage(String playlistId) async {
    await _delete('/playlists/${Uri.encodeComponent(playlistId)}/image');
  }

  /// Fetches the user's custom artist image versions manifest. Returns a map of
  /// normalized artistKey -> updatedAt.
  Future<Map<String, int>> getArtistImages() async {
    try {
      final json = await _get('/v2/artists/images');
      final list = json['images'];
      if (list is! List) return const <String, int>{};
      final result = <String, int>{};
      for (final item in list) {
        if (item is Map) {
          final key = item['artistKey'] as String? ?? '';
          final version = (item['updatedAt'] as num?)?.toInt();
          if (key.isNotEmpty && version != null) {
            result[key] = version;
          }
        }
      }
      return result;
    } catch (_) {
      return const <String, int>{};
    }
  }

  /// Builds the URL for an artist's synced custom image. [version]
  /// (the updatedAt timestamp) cache-busts replaced images.
  String artistImageUrl(String artistName, {int? version}) {
    final uri = Uri.parse(
      '$baseUrl/artists/${Uri.encodeComponent(artistName)}/image',
    );
    if (version == null) return uri.toString();
    return uri.replace(queryParameters: {'v': '$version'}).toString();
  }

  /// Upload/replace an artist's custom image. Returns the server's new
  /// image version (updatedAt milliseconds), or null.
  Future<int?> putArtistImage(
    String artistName, {
    required Uint8List bytes,
    required String contentType,
  }) async {
    try {
      final uri = _withDeviceParams(Uri.parse(
        '$baseUrl/artists/${Uri.encodeComponent(artistName)}/image',
      ));
      final headers = <String, String>{'Content-Type': contentType};
      if (sessionToken != null) {
        headers['Authorization'] = 'Bearer $sessionToken';
      }
      final response = await _client
          .put(uri, headers: headers, body: bytes)
          .timeout(timeout);
      final json = _handleResponse(response);
      final image = json['image'];
      if (image is! Map) return null;
      return (image['updatedAt'] as num?)?.toInt();
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        code: ApiErrorCodes.serverError,
        message: 'Network error: $e',
      );
    }
  }

  Future<void> deleteArtistImage(String artistName) async {
    await _delete('/artists/${Uri.encodeComponent(artistName)}/image');
  }

  /// Stores an opaque license file on the server so other household
  /// devices (TVs) can fetch and verify it themselves. Admin/owner
  /// sessions only — others get an ApiException with FORBIDDEN_ADMIN.
  Future<void> putLicenseFile(String licenseFile) async {
    await _put('/license', <String, dynamic>{'licenseFile': licenseFile});
  }

  /// Fetches the Last.fm application key shared by this Ariami household.
  Future<MusicDiscoveryApiKeyConfig> getMusicDiscoveryApiKeyConfig() async {
    return MusicDiscoveryApiKeyConfig.fromJson(
      await _get('/music-discovery/config'),
    );
  }

  /// Owner-only: creates or replaces the household Last.fm application key.
  Future<MusicDiscoveryApiKeyConfig> putMusicDiscoveryApiKey(String apiKey,
      {bool onlyIfMissing = false}) async {
    return MusicDiscoveryApiKeyConfig.fromJson(
      await _put('/music-discovery/config', <String, dynamic>{
        'lastFmApiKey': apiKey,
        if (onlyIfMissing) 'onlyIfMissing': true,
      }),
    );
  }

  /// Owner-only: removes the household key. Per-device preferences remain.
  Future<MusicDiscoveryApiKeyConfig> deleteMusicDiscoveryApiKey() async {
    return MusicDiscoveryApiKeyConfig.fromJson(
      await _delete('/music-discovery/config'),
    );
  }

  /// Request a stream ticket for authenticated streaming
  /// Returns a short-lived token that can be passed as a query parameter
  Future<StreamTicketResponse> getStreamTicket(String songId,
      {String? quality}) async {
    final request = StreamTicketRequest(songId: songId, quality: quality);
    final response = await _post('/stream-ticket', request.toJson());
    return StreamTicketResponse.fromJson(response);
  }

  /// Hint the server to prepare likely upcoming streams in its transcode cache.
  Future<void> warmStreams(List<String> songIds, {String? quality}) async {
    if (songIds.isEmpty) return;
    await _post('/stream-warmup', {
      'songIds': songIds.take(3).toList(),
      if (quality != null) 'quality': quality,
    });
  }

  /// Request a long-lived download ticket for authenticated offline downloads.
  Future<DownloadTicketResponse> getDownloadTicket(String songId,
      {String? quality, String? format}) async {
    final request = DownloadTicketRequest(
      songId: songId,
      quality: quality,
      format: format,
    );
    final response = await _post('/download-ticket', request.toJson());
    return DownloadTicketResponse.fromJson(response);
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
  String getDownloadUrlWithQuality(
    String songId,
    StreamingQuality quality, {
    String? format,
  }) {
    final params = <String, String>{};
    if (quality != StreamingQuality.high || format != null) {
      params['quality'] = quality.toApiParam();
    }
    if (format != null) params['format'] = format;
    return Uri.parse('$baseUrl/download/$songId')
        .replace(queryParameters: params.isEmpty ? null : params)
        .toString();
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

  /// Get download URL with long-lived download token for authenticated downloads.
  String getDownloadUrlWithDownloadToken(String songId, String downloadToken,
      {StreamingQuality? quality, String? format}) {
    final params = <String, String>{
      'downloadToken': downloadToken,
    };

    if (quality != null &&
        (quality != StreamingQuality.high || format != null)) {
      params['quality'] = quality.toApiParam();
    }
    if (format != null) params['format'] = format;

    final uri =
        Uri.parse('$baseUrl/download/$songId').replace(queryParameters: params);
    return uri.toString();
  }

  /// Perform GET request (includes Authorization header if sessionToken is set)
  Future<Map<String, dynamic>> _get(String endpoint) async {
    try {
      final uri = _withDeviceParams(Uri.parse('$baseUrl$endpoint'));
      final headers = <String, String>{};
      if (sessionToken != null) {
        headers['Authorization'] = 'Bearer $sessionToken';
      }
      final response =
          await _client.get(uri, headers: headers).timeout(timeout);

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
      final response = await _client
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

  /// Perform PUT request (includes Authorization header if sessionToken is set)
  Future<Map<String, dynamic>> _put(
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
      final response = await _client
          .put(
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

  Future<Map<String, dynamic>> _delete(String endpoint) async {
    try {
      final uri = _withDeviceParams(Uri.parse('$baseUrl$endpoint'));
      final headers = <String, String>{};
      if (sessionToken != null) {
        headers['Authorization'] = 'Bearer $sessionToken';
      }
      final response =
          await _client.delete(uri, headers: headers).timeout(timeout);
      return _handleResponse(response);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        code: ApiErrorCodes.serverError,
        message: 'Network error: $e',
      );
    }
  }

  Future<Map<String, dynamic>> _getWithAuth(
    String endpoint,
    String sessionToken,
  ) async {
    try {
      final uri = _withDeviceParams(Uri.parse('$baseUrl$endpoint'));
      final response = await _client.get(
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

  Future<Map<String, dynamic>> _postWithAuth(
    String endpoint,
    Map<String, dynamic> body,
    String sessionToken,
  ) async {
    try {
      final uri = _withDeviceParams(Uri.parse('$baseUrl$endpoint'));
      final response = await _client
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

  Map<String, dynamic> _handleResponse(http.Response response) {
    // Explicitly decode as UTF-8 to handle non-ASCII characters correctly
    final body = utf8.decode(response.bodyBytes);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(body) as Map<String, dynamic>;
    } else {
      try {
        final errorJson = jsonDecode(body) as Map<String, dynamic>;
        if (errorJson.containsKey('musicAvailability')) {
          musicAvailability =
              MusicAvailability.fromJson(errorJson['musicAvailability']);
          onMusicAvailabilityChanged?.call(musicAvailability);
        }
        final errorResponse = ErrorResponse.fromJson(errorJson);

        if (response.statusCode == 401 &&
            (errorResponse.error.code == ApiErrorCodes.sessionExpired ||
                errorResponse.error.code == ApiErrorCodes.authRequired)) {
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
        if (e is ApiException) rethrow;

        throw ApiException(
          code: ApiErrorCodes.serverError,
          message: 'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        );
      }
    }
  }

  void _throwIfByteResponseFailed(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    try {
      final body = utf8.decode(response.bodyBytes);
      final errorJson = jsonDecode(body) as Map<String, dynamic>;
      final errorResponse = ErrorResponse.fromJson(errorJson);

      if (response.statusCode == 401 &&
          (errorResponse.error.code == ApiErrorCodes.sessionExpired ||
              errorResponse.error.code == ApiErrorCodes.authRequired)) {
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
      if (e is ApiException) rethrow;

      throw ApiException(
        code: ApiErrorCodes.serverError,
        message: 'HTTP ${response.statusCode}: ${response.reasonPhrase}',
      );
    }
  }
}

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

  bool isCode(String errorCode) => code == errorCode;
}
