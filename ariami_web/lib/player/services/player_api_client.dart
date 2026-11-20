import 'package:ariami_core/models/artwork_batch_codec.dart';
import 'package:ariami_core/models/auth_models.dart' show StreamTicketResponse;
import 'package:ariami_core/models/library_curation.dart';
import 'package:ariami_core/models/lyrics_models.dart';
import 'package:ariami_core/models/music_availability.dart';
import 'dart:async';
import 'dart:convert';

import 'package:ariami_core/models/listening_stats_models.dart'
    show SpotifyImportStatus;
import 'package:ariami_core/services/recommendations/music_discovery_api_key_config.dart';
import 'package:ariami_core/services/recommendations/music_recommendation_models.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/player_models.dart';

/// Thrown when the server returns an error response.
class PlayerApiException implements Exception {
  final String code;
  final String message;
  final int? statusCode;

  PlayerApiException(this.code, this.message, {this.statusCode});

  bool get isAuthError =>
      statusCode == 401 ||
      code == 'AUTH_REQUIRED' ||
      code == 'SESSION_EXPIRED' ||
      code == 'INVALID_SESSION';

  bool get isAlreadyLoggedInElsewhere =>
      code == 'ALREADY_LOGGED_IN_OTHER_DEVICE';

  @override
  String toString() => 'PlayerApiException($code): $message';
}

/// HTTP client for talking to an Ariami server (local or remote).
///
/// Unifies the "server + client" and "remote client" cases: in both we speak
/// the same HTTP API. For the embedded local server callers pass a [baseUrl]
/// of `http://127.0.0.1:<port>`.
class PlayerApiClient {
  MusicAvailability musicAvailability = MusicAvailability.unknown;

  PlayerApiClient({
    required this.baseUrl,
    required this.deviceId,
    required this.deviceName,
    this.sessionToken,
    this.timeout = const Duration(seconds: 12),
  });

  /// Origin without trailing slash, e.g. `http://127.0.0.1:8080`.
  final String baseUrl;
  final String deviceId;
  final String deviceName;
  Duration timeout;

  String? sessionToken;

  /// Invoked when the server reports the session is no longer valid.
  void Function()? onSessionExpired;

  /// Invoked when a request cannot reach the server.
  void Function()? onNetworkError;

  final http.Client _client = http.Client();

  String get _apiBase => '$baseUrl/api';

  Map<String, String> _headers({
    bool json = false,
    String accept = 'application/json',
  }) {
    return <String, String>{
      if (json) 'Content-Type': 'application/json; charset=utf-8',
      'Accept': accept,
      if (sessionToken != null && sessionToken!.isNotEmpty)
        'Authorization': 'Bearer $sessionToken',
    };
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final params = <String, String>{
      'deviceId': deviceId,
      'deviceName': deviceName,
      ...?query,
    };
    return Uri.parse('$_apiBase$path').replace(queryParameters: params);
  }

  Future<PlayerServerInfo> fetchServerInfo(
    String host, {
    String scheme = 'http',
  }) async {
    final json = await _getJson('/server-info');
    return PlayerServerInfo.fromJson(json, host: host, scheme: scheme);
  }

  /// Re-reads this endpoint's capability advertisement immediately before a
  /// Spotify-only reset. This must not rely on connection-time metadata: a
  /// server can be rolled back at the same address while the client remains
  /// open, and old servers interpret the source body as a full stats wipe.
  Future<bool> supportsListeningSourceResetNow() async {
    final uri = Uri.parse(baseUrl);
    final info = await fetchServerInfo(
      uri.host,
      scheme: uri.scheme.isEmpty ? 'http' : uri.scheme,
    );
    return info.supportsListeningSourceReset;
  }

  Future<bool> ping() async {
    try {
      final response = await _getJson('/ping');
      musicAvailability =
          MusicAvailability.fromJson(response['musicAvailability']);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<AuthSession> login(
    String username,
    String password, {
    bool allowOtherDeviceTakeover = false,
  }) async {
    final json = await _postJson('/auth/login', <String, dynamic>{
      'username': username,
      'password': password,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'allowOtherDeviceTakeover': allowOtherDeviceTakeover,
    });
    final session = AuthSession.fromLoginJson(json);
    sessionToken = session.sessionToken;
    return session;
  }

  Future<void> register(
    String username,
    String password,
    String registrationToken,
  ) async {
    await _postJson('/auth/register', <String, dynamic>{
      'username': username,
      'password': password,
      'registrationToken': registrationToken,
    });
  }

  Future<void> connectClient({required String platform}) async {
    await _postJson('/connect', <String, dynamic>{
      'deviceId': deviceId,
      'deviceName': deviceName,
      'appVersion': '5.0 Preview',
      'platform': platform,
    });
  }

  /// One protected request: succeeds (even if empty) only with a valid token.
  Future<void> checkSession() => _getJson('/v2/playlists', {'limit': '1'});

  Future<PlayerAccount> fetchMe() async {
    final json = await _getJson('/me');
    return PlayerAccount.fromJson(json);
  }

  Future<Uint8List?> fetchMyAvatar() async {
    try {
      final response = await _client
          .get(
            _uri('/me/avatar'),
            headers: _headers(accept: 'image/*,application/json'),
          )
          .timeout(timeout);
      if (response.statusCode == 404) return null;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.bodyBytes;
      }
      _decode(response);
      return null;
    } on PlayerApiException {
      rethrow;
    } catch (e) {
      throw _networkError(e);
    }
  }

  Future<void> logout() async {
    if (sessionToken == null) return;
    try {
      await _postJson('/auth/logout', <String, dynamic>{});
    } catch (_) {
      // Best-effort.
    }
    sessionToken = null;
  }

  /// Minimum catalog `syncToken` observed across `/v2` list pages since the
  /// last [resetCatalogSyncTokenCapture]. The minimum is the safe resume
  /// point: any change committed after it is replayed by `/v2/changes`, and
  /// upserts are idempotent. Null when no page reported a token (old server,
  /// or a test fake bypassing the pagers).
  int? get capturedCatalogSyncToken => _capturedCatalogSyncToken;
  int? _capturedCatalogSyncToken;

  void resetCatalogSyncTokenCapture() => _capturedCatalogSyncToken = null;

  void _noteCatalogSyncToken(Object? raw) {
    final token = raw is num ? raw.toInt() : null;
    if (token == null) return;
    final current = _capturedCatalogSyncToken;
    _capturedCatalogSyncToken =
        current == null || token < current ? token : current;
  }

  Future<List<Album>> fetchAllAlbums({int pageLimit = 200}) async {
    final albums = <Album>[];
    String? cursor;
    var guard = 0;
    do {
      final json = await _getJson('/v2/albums', <String, String>{
        'limit': '$pageLimit',
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      });
      _noteCatalogSyncToken(json['syncToken']);
      final page = (json['albums'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => Album.fromJson(e as Map<String, dynamic>))
          .toList();
      albums.addAll(page);
      final pageInfo = json['pageInfo'] as Map<String, dynamic>?;
      final hasMore = pageInfo?['hasMore'] as bool? ?? false;
      cursor = hasMore ? (pageInfo?['nextCursor'] as String?) : null;
      guard++;
    } while (cursor != null && cursor.isNotEmpty && guard < 1000);
    return albums;
  }

  Future<List<Track>> fetchAllSongs({int pageLimit = 500}) async {
    final tracks = <Track>[];
    String? cursor;
    var guard = 0;
    do {
      final json = await _getJson('/v2/songs', <String, String>{
        'limit': '$pageLimit',
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      });
      _noteCatalogSyncToken(json['syncToken']);
      final page = (json['songs'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => Track.fromJson(e as Map<String, dynamic>))
          .toList();
      tracks.addAll(page);
      final pageInfo = json['pageInfo'] as Map<String, dynamic>?;
      final hasMore = pageInfo?['hasMore'] as bool? ?? false;
      cursor = hasMore ? (pageInfo?['nextCursor'] as String?) : null;
      guard++;
    } while (cursor != null && cursor.isNotEmpty && guard < 5000);
    return tracks;
  }

  Future<List<PlaylistSummary>> fetchPlaylists({int pageLimit = 200}) async {
    final playlists = <PlaylistSummary>[];
    String? cursor;
    var guard = 0;
    do {
      final json = await _getJson('/v2/playlists', <String, String>{
        'limit': '$pageLimit',
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      });
      _noteCatalogSyncToken(json['syncToken']);
      final page = (json['playlists'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => PlaylistSummary.fromJson(e as Map<String, dynamic>))
          .toList();
      playlists.addAll(page);
      final pageInfo = json['pageInfo'] as Map<String, dynamic>?;
      final hasMore = pageInfo?['hasMore'] as bool? ?? false;
      cursor = hasMore ? (pageInfo?['nextCursor'] as String?) : null;
      guard++;
    } while (cursor != null && cursor.isNotEmpty && guard < 1000);
    return playlists;
  }

  /// Fetches one page of the interleaved full-catalog feed
  /// (`/v2/bootstrap`). [cursor] resumes a previous partial pass.
  Future<V2BootstrapPage> fetchBootstrapPage({
    String? cursor,
    int limit = 500,
  }) async {
    final json = await _getJson('/v2/bootstrap', <String, String>{
      'limit': '$limit',
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    });
    return V2BootstrapPage.fromJson(json);
  }

  Future<V2ChangesPage> fetchChangesSince(int since, {int limit = 500}) async {
    final json = await _getJson('/v2/changes', <String, String>{
      'since': '$since',
      'limit': '$limit',
    });
    return V2ChangesPage.fromJson(json);
  }

  Future<AlbumDetail> fetchAlbumDetail(String albumId) async {
    final json = await _getJson('/albums/${Uri.encodeComponent(albumId)}');
    return AlbumDetail.fromJson(json);
  }

  /// Fetches lyrics for the given [songId], or null if unavailable.
  Future<SongLyrics?> fetchLyrics(String songId) async {
    try {
      final json = await _getJson('/lyrics/${Uri.encodeComponent(songId)}');
      return SongLyrics.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<List<PinnedMediaItem>> fetchPins() async {
    final json = await _getJson('/pins');
    return (json['pins'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map((item) => PinnedMediaItem.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList(growable: false);
  }

  Future<void> pin(String type, String targetId) async {
    await _postJson('/pins', <String, dynamic>{
      'type': type,
      'targetId': targetId,
    });
  }

  Future<void> unpin(String type, String targetId) async {
    await _deleteJson(
      '/pins/${Uri.encodeComponent(type)}/${Uri.encodeComponent(targetId)}',
    );
  }

  Future<List<HiddenMediaItem>> fetchHidden() async {
    final json = await _getJson('/hidden');
    return (json['hidden'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map((item) => HiddenMediaItem.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList(growable: false);
  }

  /// Hides a whole selection in one request. The server skips rows it can't
  /// accept rather than failing the batch.
  Future<void> hide(Iterable<({String type, String targetId})> targets) async {
    await _postJson('/hidden', <String, dynamic>{
      'items': [
        for (final target in targets)
          {'type': target.type, 'targetId': target.targetId},
      ],
    });
  }

  Future<void> unhide(String type, String targetId) async {
    await _deleteJson(
      '/hidden/${Uri.encodeComponent(type)}/${Uri.encodeComponent(targetId)}',
    );
  }

  Future<UserLibraryCuration> fetchCuration() async {
    final json = await _getJson('/v2/curation');
    return UserLibraryCuration.fromJson(json);
  }

  Future<UserLibraryCuration> putCuration(Map<String, dynamic> body) async {
    final json = await _putJson('/v2/curation', body);
    return UserLibraryCuration.fromJson(json);
  }

  /// Fetches playlist edits together with the custom cover-image manifest
  /// (playlist id -> image version) the server returns on the same endpoint.
  Future<({List<PlaylistEdit> edits, Map<String, int> imageVersions})>
      fetchPlaylistEditsAndImages() async {
    final json = await _getJson('/playlists/edits');
    final imageVersions = <String, int>{};
    for (final item in json['images'] as List<dynamic>? ?? const <dynamic>[]) {
      if (item is! Map) continue;
      final playlistId = item['playlistId'];
      final updatedAt = item['updatedAt'];
      if (playlistId is String && updatedAt is num) {
        imageVersions[playlistId] = updatedAt.toInt();
      }
    }
    return (edits: _parsePlaylistEdits(json), imageVersions: imageVersions);
  }

  List<PlaylistEdit> _parsePlaylistEdits(Map<String, dynamic> json) =>
      (json['edits'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((item) => PlaylistEdit.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList(growable: false);

  Future<void> putPlaylistEdit(
    String playlistId, {
    required List<String> songIds,
    String? name,
    required List<String> baseSnapshot,
  }) async {
    await _putJson(
      '/playlists/${Uri.encodeComponent(playlistId)}/edit',
      <String, dynamic>{
        'songIds': songIds,
        'name': name,
        'baseSnapshot': baseSnapshot,
      },
    );
  }

  Future<void> deletePlaylistEdit(String playlistId) async {
    await _deleteJson('/playlists/${Uri.encodeComponent(playlistId)}/edit');
  }

  /// Uploads/replaces a playlist's custom cover image in the account's image
  /// store. Returns the server's new image version (updatedAt milliseconds),
  /// or null if the response omitted it.
  Future<int?> putPlaylistImage(
    String playlistId, {
    required Uint8List bytes,
    required String contentType,
  }) async {
    try {
      final response = await _client
          .put(
            _uri('/playlists/${Uri.encodeComponent(playlistId)}/image'),
            headers: {..._headers(), 'Content-Type': contentType},
            body: bytes,
          )
          .timeout(timeout);
      final json = _decode(response);
      final image = json['image'];
      if (image is! Map) return null;
      return (image['updatedAt'] as num?)?.toInt();
    } on PlayerApiException {
      rethrow;
    } catch (e) {
      throw _networkError(e);
    }
  }

  Future<void> deletePlaylistImage(String playlistId) async {
    await _deleteJson('/playlists/${Uri.encodeComponent(playlistId)}/image');
  }

  /// Fetches the user's custom artist image versions manifest. Returns a map of
  /// normalized artistKey -> updatedAt.
  Future<Map<String, int>> fetchArtistImages() async {
    try {
      final json = await _getJson('/v2/artists/images');
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

  /// Uploads/replaces an artist's custom image in the account's image store.
  /// Returns the server's new image version (updatedAt milliseconds), or null.
  Future<int?> putArtistImage(
    String artistName, {
    required Uint8List bytes,
    required String contentType,
  }) async {
    try {
      final response = await _client
          .put(
            _uri('/artists/${Uri.encodeComponent(artistName)}/image'),
            headers: {..._headers(), 'Content-Type': contentType},
            body: bytes,
          )
          .timeout(timeout);
      final json = _decode(response);
      final image = json['image'];
      if (image is! Map) return null;
      return (image['updatedAt'] as num?)?.toInt();
    } on PlayerApiException {
      rethrow;
    } catch (e) {
      throw _networkError(e);
    }
  }

  Future<void> deleteArtistImage(String artistName) async {
    await _deleteJson('/artists/${Uri.encodeComponent(artistName)}/image');
  }

  /// Fetches every household license file stored on the server (newest
  /// last), empty when none is stored. Older servers expose only a single
  /// `licenseFile`. The server relays the files verbatim; callers verify
  /// them.
  Future<List<String>> fetchLicenseFiles() async {
    final json = await _getJson('/license');
    final files = json['licenseFiles'];
    if (files is List) {
      return files
          .whereType<String>()
          .where((file) => file.isNotEmpty)
          .toList(growable: false);
    }
    final licenseFile = json['licenseFile'];
    return licenseFile is String && licenseFile.isNotEmpty
        ? [licenseFile]
        : const [];
  }

  /// Stores the household license file on the server so other devices can
  /// fetch it. Admin/owner sessions only; returns false when rejected.
  Future<bool> putLicenseFile(String licenseFile) async {
    try {
      await _putJson('/license', <String, dynamic>{
        'licenseFile': licenseFile,
      });
      return true;
    } on PlayerApiException {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Household music-discovery configuration
  // ---------------------------------------------------------------------------

  Future<MusicDiscoveryApiKeyConfig> fetchMusicDiscoveryApiKeyConfig() async {
    return MusicDiscoveryApiKeyConfig.fromJson(
      await _getJson('/music-discovery/config'),
    );
  }

  /// Owner-only: creates or replaces the household Last.fm application key.
  Future<MusicDiscoveryApiKeyConfig> putMusicDiscoveryApiKey(String apiKey,
      {bool onlyIfMissing = false}) async {
    return MusicDiscoveryApiKeyConfig.fromJson(
      await _putJson('/music-discovery/config', <String, dynamic>{
        'lastFmApiKey': apiKey,
        if (onlyIfMissing) 'onlyIfMissing': true,
      }),
    );
  }

  /// Owner-only: removes the household key. Per-device preferences remain.
  Future<MusicDiscoveryApiKeyConfig> deleteMusicDiscoveryApiKey() async {
    return MusicDiscoveryApiKeyConfig.fromJson(
      await _deleteJson('/music-discovery/config'),
    );
  }

  /// Owner-only: updates or clears the optional wishlist webhook URL.
  Future<MusicDiscoveryApiKeyConfig> putMusicDiscoveryWebhookUrl(
    String? webhookUrl,
  ) async {
    return MusicDiscoveryApiKeyConfig.fromJson(
      await _putJson('/music-discovery/config', <String, dynamic>{
        'webhookUrl': webhookUrl ?? '',
      }),
    );
  }

  Future<Map<String, dynamic>> fetchMusicDiscoveryWishlist() async {
    return _getJson('/music-discovery/wishlist');
  }

  Future<Map<String, dynamic>> addMusicDiscoveryWishlistItem(
    MusicRecommendation item,
  ) async {
    return _postJson('/music-discovery/wishlist', item.toJson());
  }

  Future<Map<String, dynamic>> removeMusicDiscoveryWishlistItem(
    String key,
  ) async {
    return _deleteJson(
      '/music-discovery/wishlist',
      <String, String>{'key': key},
    );
  }

  /// Uploads a batch of listening events (idempotent by eventId).
  Future<Map<String, dynamic>> postListeningEvents(
    List<Map<String, dynamic>> events,
  ) async {
    return _postJson('/v2/listening/events', <String, dynamic>{
      'events': events,
    });
  }

  Future<Map<String, dynamic>> getListeningSummary() async {
    return _getJson('/v2/listening/summary');
  }

  /// Account-wide listened milliseconds per local day (`yyyy-mm-dd`).
  Future<Map<String, int>> getListeningDaily({int days = 130}) async {
    final json = await _getJson('/v2/listening/daily', <String, String>{
      'days': '$days',
    });
    final raw = json['days'];
    if (raw is! Map) return const <String, int>{};
    return <String, int>{
      for (final entry in raw.entries)
        if (entry.value is num) '${entry.key}': (entry.value as num).toInt(),
    };
  }

  Future<List<Map<String, dynamic>>> getListeningRecent({int days = 7}) async {
    final json = await _getJson('/v2/listening/recent', <String, String>{
      'days': '$days',
    });
    return (json['songs'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  /// Totals plus top songs / credited artists / albums for one local day
  /// (`yyyy-mm-dd`). A [limit] of 0 requests every ranked entry (rejected by
  /// pre-5.x servers). Older servers without the derivation layer respond
  /// 404; callers must degrade gracefully.
  Future<Map<String, dynamic>> getListeningDay(
    String date, {
    int limit = 50,
  }) async {
    return _getJson('/v2/listening/day', <String, String>{
      'date': date,
      'limit': '$limit',
    });
  }

  /// Totals, per-day breakdown and top songs / credited artists / albums for
  /// an inclusive local-day range (`yyyy-mm-dd`).
  Future<Map<String, dynamic>> getListeningPeriod({
    required String from,
    required String to,
    int limit = 50,
  }) async {
    return _getJson('/v2/listening/period', <String, String>{
      'from': from,
      'to': to,
      'limit': '$limit',
    });
  }

  /// Top credited artists (multi-artist strings split server-side), all-time
  /// when [days] is null. A [limit] of 0 requests every artist (rejected by
  /// pre-5.x servers).
  Future<List<Map<String, dynamic>>> getListeningArtists({
    int? days,
    int limit = 50,
  }) async {
    final json = await _getJson('/v2/listening/artists', <String, String>{
      if (days != null) 'days': '$days',
      'limit': '$limit',
    });
    return (json['artists'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  /// Top albums, all-time when [days] is null. A [limit] of 0 requests every
  /// album (rejected by pre-5.x servers).
  Future<List<Map<String, dynamic>>> getListeningAlbums({
    int? days,
    int limit = 50,
  }) async {
    final json = await _getJson('/v2/listening/albums', <String, String>{
      if (days != null) 'days': '$days',
      'limit': '$limit',
    });
    return (json['albums'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  /// What the signed-in account's Spotify import holds. Null when the server
  /// predates the endpoint (404) — old servers simply leave the import
  /// undescribed rather than failing the stats view.
  Future<SpotifyImportStatus?> getSpotifyImportStatus() async {
    try {
      return SpotifyImportStatus.fromJson(
        await _getJson('/v2/listening/import-status'),
      );
    } on PlayerApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Permanently wipes listening history for the signed-in account.
  Future<void> postListeningReset() async {
    await _postJson('/v2/listening/reset', const <String, dynamic>{});
  }

  /// Deletes only the Spotify-imported listening events for the signed-in
  /// account (the "undo import" path). Returns how many events were deleted.
  Future<int> postSpotifyImportReset() async {
    final json = await _postJson(
      '/v2/listening/reset',
      const <String, dynamic>{'source': 'spotify'},
    );
    return json['deleted'] as int? ?? 0;
  }

  Future<String> requestStreamToken(
    String songId, {
    StreamQuality quality = StreamQuality.high,
    String? format,
  }) async {
    final ticket = await requestStreamTicket(
      songId,
      quality: quality,
      format: format,
    );
    return ticket.streamToken;
  }

  /// Requests a stream ticket and returns the full response, including the
  /// source file's bitrate/format when the server reports them (newer
  /// servers; null otherwise) — used by the debug overlay to show the real
  /// streamed quality.
  Future<StreamTicketResponse> requestStreamTicket(
    String songId, {
    StreamQuality quality = StreamQuality.high,
    String? format,
  }) async {
    final json = await _postJson('/stream-ticket', <String, dynamic>{
      'songId': songId,
      'quality': quality.apiParam,
      if (format != null) 'format': format,
    });
    final token = json['streamToken'] as String?;
    if (token == null || token.isEmpty) {
      throw PlayerApiException('SERVER_ERROR', 'Missing stream token');
    }
    return StreamTicketResponse.fromJson(json);
  }

  String streamUrl(
    String songId,
    String streamToken, {
    StreamQuality quality = StreamQuality.high,
    String? format,
  }) {
    final params = <String, String>{
      'streamToken': streamToken,
      if (quality != StreamQuality.high) 'quality': quality.apiParam,
      if (format != null) 'format': format,
    };
    return Uri.parse('$_apiBase/stream/${Uri.encodeComponent(songId)}')
        .replace(queryParameters: params)
        .toString();
  }

  /// Requests a long-lived download token for [songId] at [quality], used for
  /// offline downloads (mirrors mobile's `/download-ticket` flow).
  Future<String> requestDownloadTicket(
    String songId, {
    StreamQuality quality = StreamQuality.high,
    String? format,
  }) async {
    final json = await _postJson('/download-ticket', <String, dynamic>{
      'songId': songId,
      'quality': quality.apiParam,
      if (format != null) 'format': format,
    });
    final token = json['downloadToken'] as String?;
    if (token == null || token.isEmpty) {
      throw PlayerApiException('SERVER_ERROR', 'Missing download token');
    }
    return token;
  }

  /// Builds the URL that serves the full audio file for a download token.
  /// The token authenticates the request, so no headers are needed.
  String downloadUrl(
    String songId,
    String downloadToken, {
    StreamQuality quality = StreamQuality.high,
    String? format,
  }) {
    return Uri.parse('$_apiBase/download/${Uri.encodeComponent(songId)}')
        .replace(queryParameters: <String, String>{
      'downloadToken': downloadToken,
      'quality': quality.apiParam,
      if (format != null) 'format': format,
    }).toString();
  }

  /// Builds an artwork URL for an album. The Authorization header is supplied
  /// separately via [artworkHeaders] because `Image.network` sends headers.
  /// [medium] asks for the 640px variant; servers without it send full size.
  String albumArtworkUrl(
    String albumId, {
    bool thumbnail = false,
    bool medium = false,
  }) {
    final uri = Uri.parse('$_apiBase/artwork/${Uri.encodeComponent(albumId)}')
        .replace(queryParameters: {'size': _artworkSize(thumbnail, medium)});
    return uri.toString();
  }

  String songArtworkUrl(
    String songId, {
    bool thumbnail = false,
    bool medium = false,
  }) {
    final uri =
        Uri.parse('$_apiBase/song-artwork/${Uri.encodeComponent(songId)}')
            .replace(queryParameters: {'size': _artworkSize(thumbnail, medium)});
    return uri.toString();
  }

  static String _artworkSize(bool thumbnail, bool medium) =>
      thumbnail ? 'thumbnail' : (medium ? 'medium' : 'full');

  /// Builds the URL for a playlist's synced custom cover image. [version]
  /// (the manifest's updatedAt) cache-busts replaced images.
  String playlistImageUrl(String playlistId, {int? version}) {
    final uri = Uri.parse(
      '$_apiBase/playlists/${Uri.encodeComponent(playlistId)}/image',
    );
    if (version == null) return uri.toString();
    return uri.replace(queryParameters: {'v': '$version'}).toString();
  }

  /// Builds the URL for an artist's synced custom image. [version]
  /// (the updatedAt timestamp) cache-busts replaced images.
  String artistImageUrl(String artistName, {int? version}) {
    final uri = Uri.parse(
      '$_apiBase/artists/${Uri.encodeComponent(artistName)}/image',
    );
    if (version == null) return uri.toString();
    return uri.replace(queryParameters: {'v': '$version'}).toString();
  }

  Map<String, String> get artworkHeaders => <String, String>{
        if (kIsWeb) 'Accept': 'image/webp,image/jpeg,*/*',
        if (sessionToken != null && sessionToken!.isNotEmpty)
          'Authorization': 'Bearer $sessionToken',
      };

  /// Fetches up to 50 thumbnails in a single HTTP request. Returns `null` if
  /// the server does not support `/api/artwork/batch` (older server).
  Future<List<ArtworkBatchItem>?> fetchArtworkBatch({
    required List<String> albumIds,
    required List<String> songIds,
    String size = 'thumbnail',
  }) async {
    if (albumIds.isEmpty && songIds.isEmpty) {
      return const <ArtworkBatchItem>[];
    }
    final response = await _client
        .post(
          Uri.parse('$_apiBase/artwork/batch'),
          headers: <String, String>{
            'Content-Type': 'application/json; charset=utf-8',
            'Accept': kIsWeb
                ? 'application/octet-stream, image/webp, image/jpeg'
                : 'application/octet-stream',
            if (sessionToken != null && sessionToken!.isNotEmpty)
              'Authorization': 'Bearer $sessionToken',
          },
          body: jsonEncode(<String, dynamic>{
            'size': size,
            if (kIsWeb) 'format': 'webp',
            'albums': albumIds,
            'songs': songIds,
          }),
        )
        .timeout(timeout);
    if (response.statusCode == 404 || response.statusCode == 405) {
      return null;
    }
    if (response.statusCode != 200) {
      throw PlayerApiException(
        'ARTWORK_BATCH_ERROR',
        'Batch artwork failed (HTTP ${response.statusCode})',
        statusCode: response.statusCode,
      );
    }
    return ArtworkBatchCodec.decode(response.bodyBytes);
  }

  Future<Map<String, dynamic>> _getJson(
    String path, [
    Map<String, String>? query,
  ]) async {
    try {
      final response =
          await _client.get(_uri(path, query), headers: _headers()).timeout(
                timeout,
              );
      return _decode(response);
    } on PlayerApiException {
      rethrow;
    } catch (e) {
      throw _networkError(e);
    }
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _client
          .post(
            _uri(path),
            headers: _headers(json: true),
            body: jsonEncode(body),
          )
          .timeout(timeout);
      return _decode(response);
    } on PlayerApiException {
      rethrow;
    } catch (e) {
      throw _networkError(e);
    }
  }

  Future<Map<String, dynamic>> _putJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _client
          .put(
            _uri(path),
            headers: _headers(json: true),
            body: jsonEncode(body),
          )
          .timeout(timeout);
      return _decode(response);
    } on PlayerApiException {
      rethrow;
    } catch (e) {
      throw _networkError(e);
    }
  }

  Future<Map<String, dynamic>> _deleteJson(
    String path, [
    Map<String, String>? query,
  ]) async {
    try {
      final response = await _client
          .delete(_uri(path, query), headers: _headers())
          .timeout(timeout);
      return _decode(response);
    } on PlayerApiException {
      rethrow;
    } catch (e) {
      throw _networkError(e);
    }
  }

  PlayerApiException _networkError(Object error) {
    onNetworkError?.call();
    return PlayerApiException('NETWORK_ERROR', 'Network error: $error');
  }

  Map<String, dynamic> _decode(http.Response response) {
    final body = utf8.decode(response.bodyBytes);
    Map<String, dynamic> json;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (body.isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    }

    String code = 'SERVER_ERROR';
    String message = 'HTTP ${response.statusCode}';
    try {
      json = jsonDecode(body) as Map<String, dynamic>;
      if (json.containsKey('musicAvailability')) {
        musicAvailability =
            MusicAvailability.fromJson(json['musicAvailability']);
      }
      final error = json['error'];
      if (error is Map<String, dynamic>) {
        code = error['code'] as String? ?? code;
        message = error['message'] as String? ?? message;
      }
    } catch (_) {}

    final exception =
        PlayerApiException(code, message, statusCode: response.statusCode);
    if (exception.isAuthError && sessionToken != null) {
      onSessionExpired?.call();
    }
    throw exception;
  }

  void dispose() => _client.close();
}
