/// Self-contained data models for the desktop music player client.
///
/// These mirror the JSON shapes returned by the Ariami HTTP server (see
/// `ariami_core` HTTP handlers and the mobile client models). They are kept
/// independent from the mobile package so the desktop player can evolve on its
/// own.
library;

import 'package:ariami_core/services/library/library_genre_index.dart'
    show LibraryGenreSource;

class PlayerServerInfo {
  final String scheme;

  /// The endpoint this client is currently talking to (used for [baseUrl]).
  final String host;
  final int port;
  final String name;
  final String version;
  final bool authRequired;
  final bool legacyMode;

  /// Whether the server exposes the Spotify-import-only reset endpoint.
  /// Fail-closed: only a literal JSON `true` enables it, so older servers
  /// (which don't send the flag at all) read as unsupported.
  final bool supportsListeningSourceReset;

  final String? lanServer;

  /// The Tailscale (remote) IP the server advertises, if any. Mirrors the
  /// mobile client: when only `server`/`lanServer` are present and they differ,
  /// `server` is treated as the remote/Tailscale endpoint.
  final String? tailscaleServer;
  final String? lanServerAlias;
  final String? tailscaleServerAlias;

  const PlayerServerInfo({
    this.scheme = 'http',
    required this.host,
    required this.port,
    required this.name,
    required this.version,
    this.authRequired = false,
    this.legacyMode = true,
    this.supportsListeningSourceReset = false,
    this.lanServer,
    this.tailscaleServer,
    this.lanServerAlias,
    this.tailscaleServerAlias,
  });

  String get baseUrl {
    final defaultPort = scheme == 'https' ? 443 : 80;
    final portSuffix = port == defaultPort ? '' : ':$port';
    return '$scheme://${_urlHost(host)}$portSuffix';
  }

  /// A stable identifier for this server across LAN/Tailscale endpoint
  /// switches, used to key the persisted session token so it survives the
  /// active [host] changing (e.g. LAN at home, Tailscale away).
  String get stableKey => tailscaleServer ?? lanServer ?? host;

  /// Every address that may have identified this server. Session tokens are
  /// stored under each alias so adding/removing Tailscale later does not make a
  /// valid login appear to have vanished.
  Set<String> get endpointAliases => <String>{
        host,
        if (lanServer != null) lanServer!,
        if (tailscaleServer != null) tailscaleServer!,
      }..removeWhere((value) => value.trim().isEmpty);

  factory PlayerServerInfo.fromJson(
    Map<String, dynamic> json, {
    required String host,
    String scheme = 'http',
  }) {
    final advertised = json['server'] as String?;
    final lanServer = json['lanServer'] as String?;
    final explicitTailscale = json['tailscaleServer'] as String?;
    // Match mobile's derivation: if the advertised `server` differs from the
    // LAN address, the advertised one is the remote/Tailscale endpoint.
    final derivedTailscale = explicitTailscale ??
        ((lanServer != null && advertised != null && lanServer != advertised)
            ? advertised
            : null);

    return PlayerServerInfo(
      scheme: scheme,
      host: host,
      port: json['port'] as int? ?? 8080,
      name: json['name'] as String? ?? 'Ariami Server',
      version: json['version'] as String? ?? 'unknown',
      authRequired: json['authRequired'] as bool? ?? false,
      legacyMode: json['legacyMode'] as bool? ?? true,
      // Fail-closed: absent, null, a wrong type, or false all read as false.
      supportsListeningSourceReset:
          json['supportsListeningSourceReset'] == true,
      lanServer: (lanServer != null && lanServer.isNotEmpty) ? lanServer : null,
      tailscaleServer: (derivedTailscale != null && derivedTailscale.isNotEmpty)
          ? derivedTailscale
          : null,
      lanServerAlias: json['lanServerAlias'] as String?,
      tailscaleServerAlias: json['tailscaleServerAlias'] as String?,
    );
  }

  PlayerServerInfo copyWith({
    String? scheme,
    String? host,
    int? port,
    String? name,
    String? version,
    bool? authRequired,
    bool? legacyMode,
    bool? supportsListeningSourceReset,
    String? lanServer,
    String? tailscaleServer,
    String? lanServerAlias,
    String? tailscaleServerAlias,
  }) {
    return PlayerServerInfo(
      scheme: scheme ?? this.scheme,
      host: host ?? this.host,
      port: port ?? this.port,
      name: name ?? this.name,
      version: version ?? this.version,
      authRequired: authRequired ?? this.authRequired,
      legacyMode: legacyMode ?? this.legacyMode,
      supportsListeningSourceReset:
          supportsListeningSourceReset ?? this.supportsListeningSourceReset,
      lanServer: lanServer ?? this.lanServer,
      tailscaleServer: tailscaleServer ?? this.tailscaleServer,
      lanServerAlias: lanServerAlias ?? this.lanServerAlias,
      tailscaleServerAlias: tailscaleServerAlias ?? this.tailscaleServerAlias,
    );
  }

  @override
  String toString() =>
      'PlayerServerInfo($scheme://$host:$port, $name v$version, auth=$authRequired, '
      'lan=$lanServer, tailscale=$tailscaleServer)';
}

String _urlHost(String host) {
  final value = host.trim();
  if (value.contains(':') && !(value.startsWith('[') && value.endsWith(']'))) {
    return '[$value]';
  }
  return value;
}

class Album {
  final String id;
  final String title;
  final String artist;

  /// Relative artwork path supplied by the server (e.g. `/api/artwork/<id>`),
  /// or null when the album has no embedded artwork.
  final String? coverArtPath;
  final int songCount;
  final int durationSeconds;

  const Album({
    required this.id,
    required this.title,
    required this.artist,
    this.coverArtPath,
    this.songCount = 0,
    this.durationSeconds = 0,
  });

  factory Album.fromJson(Map<String, dynamic> json) {
    final title = json['title'] as String?;
    final artist = json['artist'] as String?;
    return Album(
      id: json['id'] as String,
      title:
          (title != null && title.trim().isNotEmpty) ? title : 'Unknown Album',
      artist: (artist != null && artist.trim().isNotEmpty)
          ? artist
          : 'Unknown Artist',
      coverArtPath: json['coverArt'] as String?,
      songCount: json['songCount'] as int? ?? 0,
      durationSeconds: json['duration'] as int? ?? 0,
    );
  }

  /// Serializes to the same key shape [Album.fromJson] reads, for the offline
  /// library snapshot.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'artist': artist,
        if (coverArtPath != null) 'coverArt': coverArtPath,
        'songCount': songCount,
        'duration': durationSeconds,
      };

  @override
  bool operator ==(Object other) => other is Album && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class Track implements LibraryGenreSource {
  final String id;
  final String title;
  final String artist;
  @override
  final String? genre;
  @override
  final String? albumId;
  final String? albumTitle;
  final String? albumArtist;
  final int durationSeconds;
  final int? trackNumber;
  final bool hasLyrics;
  final bool isInstrumental;
  final String? lyrics;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    this.genre,
    this.albumId,
    this.albumTitle,
    this.albumArtist,
    this.durationSeconds = 0,
    this.trackNumber,
    this.hasLyrics = false,
    this.isInstrumental = false,
    this.lyrics,
  });

  Duration get duration => Duration(seconds: durationSeconds);

  factory Track.fromJson(
    Map<String, dynamic> json, {
    String? fallbackAlbumId,
    String? fallbackAlbumTitle,
  }) {
    return Track(
      id: json['id'] as String,
      title: (json['title'] as String?)?.isNotEmpty == true
          ? json['title'] as String
          : 'Unknown Title',
      artist: (json['artist'] as String?)?.isNotEmpty == true
          ? json['artist'] as String
          : 'Unknown Artist',
      genre: json['genre'] as String?,
      albumId: json['albumId'] as String? ?? fallbackAlbumId,
      albumTitle: json['album'] as String? ?? fallbackAlbumTitle,
      albumArtist: json['albumArtist'] as String?,
      durationSeconds: json['duration'] as int? ?? 0,
      trackNumber: json['trackNumber'] as int?,
      hasLyrics: json['hasLyrics'] as bool? ?? false,
      isInstrumental: json['isInstrumental'] as bool? ?? false,
      lyrics: json['lyrics'] as String?,
    );
  }

  /// Serializes to the same key shape [Track.fromJson] reads, so persisted
  /// playback state round-trips cleanly.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'artist': artist,
        if (genre != null) 'genre': genre,
        if (albumId != null) 'albumId': albumId,
        if (albumTitle != null) 'album': albumTitle,
        if (albumArtist != null) 'albumArtist': albumArtist,
        'duration': durationSeconds,
        if (trackNumber != null) 'trackNumber': trackNumber,
        'hasLyrics': hasLyrics,
        'isInstrumental': isInstrumental,
        if (lyrics != null) 'lyrics': lyrics,
      };

  /// [toJson] without lyrics: Connect caps every string at 2048 characters
  /// and other devices fetch lyrics themselves.
  Map<String, dynamic> toConnectJson() => toJson()..remove('lyrics');

  Track copyWith({
    String? title,
    String? artist,
    String? albumId,
    String? albumTitle,
    String? albumArtist,
    String? genre,
    int? durationSeconds,
    int? trackNumber,
    bool? hasLyrics,
    bool? isInstrumental,
    String? lyrics,
  }) {
    return Track(
      id: id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      genre: genre ?? this.genre,
      albumId: albumId ?? this.albumId,
      albumTitle: albumTitle ?? this.albumTitle,
      albumArtist: albumArtist ?? this.albumArtist,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      trackNumber: trackNumber ?? this.trackNumber,
      hasLyrics: hasLyrics ?? this.hasLyrics,
      isInstrumental: isInstrumental ?? this.isInstrumental,
      lyrics: lyrics ?? this.lyrics,
    );
  }

  @override
  bool operator ==(Object other) => other is Track && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class AlbumDetail {
  final String id;
  final String title;
  final String artist;
  final String? year;
  final String? coverArtPath;
  final List<Track> tracks;

  const AlbumDetail({
    required this.id,
    required this.title,
    required this.artist,
    this.year,
    this.coverArtPath,
    this.tracks = const <Track>[],
  });

  factory AlbumDetail.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final title = json['title'] as String? ?? 'Unknown Album';
    return AlbumDetail(
      id: id,
      title: title,
      artist: json['artist'] as String? ?? 'Unknown Artist',
      year: json['year'] as String?,
      coverArtPath: json['coverArt'] as String?,
      tracks: (json['songs'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => Track.fromJson(
                e as Map<String, dynamic>,
                fallbackAlbumId: id,
                fallbackAlbumTitle: title,
              ))
          .toList(),
    );
  }
}

class PlaylistSummary {
  final String id;
  final String name;
  final int songCount;
  final int durationSeconds;
  final List<String> songIds;

  const PlaylistSummary({
    required this.id,
    required this.name,
    this.songCount = 0,
    this.durationSeconds = 0,
    this.songIds = const <String>[],
  });

  factory PlaylistSummary.fromJson(Map<String, dynamic> json) {
    return PlaylistSummary(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Playlist',
      songCount: json['songCount'] as int? ?? 0,
      durationSeconds: json['duration'] as int? ?? 0,
      songIds: (json['songIds'] as List<dynamic>? ?? const <dynamic>[])
          .cast<String>(),
    );
  }

  /// Serializes to the same key shape [PlaylistSummary.fromJson] reads, for
  /// the offline library snapshot.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'songCount': songCount,
        'duration': durationSeconds,
        'songIds': songIds,
      };

  PlaylistSummary copyWith({
    String? name,
    int? songCount,
    int? durationSeconds,
    List<String>? songIds,
  }) {
    return PlaylistSummary(
      id: id,
      name: name ?? this.name,
      songCount: songCount ?? this.songCount,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      songIds: songIds ?? this.songIds,
    );
  }
}

class PinnedMediaItem {
  const PinnedMediaItem({
    required this.id,
    required this.type,
    required this.targetId,
    required this.sortOrder,
    required this.title,
    this.subtitle,
    this.artwork,
    this.missing = false,
  });

  final String id;
  final String type;
  final String targetId;
  final int sortOrder;
  final String title;
  final String? subtitle;
  final String? artwork;
  final bool missing;

  String get key => '$type:$targetId';

  factory PinnedMediaItem.fromJson(Map<String, dynamic> json) =>
      PinnedMediaItem(
        id: json['id'] as String? ?? '${json['type']}:${json['targetId']}',
        type: json['type'] as String,
        targetId: json['targetId'] as String,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ??
            json['name'] as String? ??
            'Unavailable item',
        subtitle: json['subtitle'] as String?,
        artwork: json['artwork'] as String?,
        missing:
            json['missing'] as bool? ?? json['unavailable'] as bool? ?? false,
      );
}

/// An album, playlist or artist the account has hidden from library browsing,
/// returned by `/api/hidden`.
///
/// [name] is resolved server-side so the unhide list can still name a target
/// whose album has since left the library ([missing]).
class HiddenMediaItem {
  const HiddenMediaItem({
    required this.type,
    required this.targetId,
    required this.name,
    this.subtitle,
    this.missing = false,
  });

  static const String albumType = 'album';
  static const String playlistType = 'playlist';
  static const String artistType = 'artist';
  static const Set<String> supportedTypes = <String>{
    albumType,
    playlistType,
    artistType,
  };

  final String type;
  final String targetId;
  final String name;
  final String? subtitle;
  final bool missing;

  String get key => '$type:$targetId';

  factory HiddenMediaItem.fromJson(Map<String, dynamic> json) =>
      HiddenMediaItem(
        type: json['type'] as String,
        targetId: json['targetId'] as String,
        name: json['name'] as String? ?? json['targetId'] as String,
        subtitle: json['subtitle'] as String?,
        missing: json['missing'] as bool? ?? false,
      );
}

class PlaylistEdit {
  const PlaylistEdit({
    required this.playlistId,
    required this.songIds,
    required this.baseSnapshot,
    this.name,
  });

  final String playlistId;
  final String? name;
  final List<String> songIds;
  final List<String> baseSnapshot;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'playlistId': playlistId,
        'name': name,
        'songIds': songIds,
        'baseSnapshot': baseSnapshot,
      };

  factory PlaylistEdit.fromJson(Map<String, dynamic> json) => PlaylistEdit(
        playlistId: json['playlistId'] as String,
        name: json['name'] as String?,
        songIds: (json['songIds'] as List<dynamic>? ?? const <dynamic>[])
            .cast<String>(),
        baseSnapshot:
            (json['baseSnapshot'] as List<dynamic>? ?? const <dynamic>[])
                .cast<String>(),
      );
}

class AuthSession {
  final String userId;
  final String username;
  final String sessionToken;

  const AuthSession({
    required this.userId,
    required this.username,
    required this.sessionToken,
  });

  factory AuthSession.fromLoginJson(Map<String, dynamic> json) {
    return AuthSession(
      userId: json['userId'] as String? ?? '',
      username: json['username'] as String? ?? '',
      sessionToken: json['sessionToken'] as String,
    );
  }
}

class PlayerAccount {
  final String userId;
  final String username;
  final bool hasAvatar;
  final int? avatarUpdatedAt;

  const PlayerAccount({
    required this.userId,
    required this.username,
    required this.hasAvatar,
    this.avatarUpdatedAt,
  });

  factory PlayerAccount.fromJson(Map<String, dynamic> json) {
    return PlayerAccount(
      userId: json['userId'] as String? ?? json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      hasAvatar: json['hasAvatar'] as bool? ?? false,
      avatarUpdatedAt: (json['avatarUpdatedAt'] as num?)?.toInt(),
    );
  }
}

enum StreamQuality { high, medium, low }

extension StreamQualityApi on StreamQuality {
  String get apiParam {
    switch (this) {
      case StreamQuality.high:
        return 'high';
      case StreamQuality.medium:
        return 'medium';
      case StreamQuality.low:
        return 'low';
    }
  }

  String get label {
    switch (this) {
      case StreamQuality.high:
        return 'High (original)';
      case StreamQuality.medium:
        return 'Medium';
      case StreamQuality.low:
        return 'Low';
    }
  }
}

/// What the audio engine is actually reading for a track — a local file or
/// an HTTP stream — recorded when the source is resolved.
enum PlaybackSourceKind { offlineFile, serverFile, downloadedFile, stream }

/// The resolved source of the current track, for the debug overlay: answers
/// "is the file or the stream at fault" by showing the real format/bitrate
/// being played, not just the requested quality.
class PlaybackSourceInfo {
  const PlaybackSourceInfo({
    required this.kind,
    required this.quality,
    this.filePath,
    this.fileSizeBytes,
    this.streamUri,
    this.sourceBitrateKbps,
    this.sourceFormat,
  });

  final PlaybackSourceKind kind;

  /// The quality the source was resolved at.
  final StreamQuality quality;

  /// Local file path for the file-backed kinds.
  final String? filePath;

  /// File size in bytes, when known; lets the overlay derive the effective
  /// bitrate of what's actually playing.
  final int? fileSizeBytes;

  /// Stream URL for [PlaybackSourceKind.stream], ticket included — use
  /// [redactedStreamUri] for anything user-visible.
  final Uri? streamUri;

  /// The source file's bitrate in kbps and format (extension), as reported by
  /// the server's stream ticket. Null on older servers; for transcoded
  /// streams this is the original file, not what is being streamed.
  final int? sourceBitrateKbps;
  final String? sourceFormat;

  /// The stream URL with the ticket removed, safe to display or copy.
  Uri? get redactedStreamUri {
    final uri = streamUri;
    if (uri == null) return null;
    final params = Map<String, String>.of(uri.queryParameters)
      ..remove('streamToken');
    return uri.replace(queryParameters: params);
  }

  String get fileExtension {
    final path = filePath;
    if (path == null) return '';
    final dot = path.lastIndexOf('.');
    return dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  }

  /// Effective bitrate in kbps of a file-backed source, derived from its size
  /// and the track's duration. Null when either is unknown.
  int? fileBitrateKbps(int durationSeconds) {
    final size = fileSizeBytes;
    if (size == null || durationSeconds <= 0) return null;
    return (size * 8 / durationSeconds / 1000).round();
  }
}

class V2ChangeEvent {
  V2ChangeEvent({
    required this.token,
    required this.op,
    required this.entityType,
    required this.entityId,
    this.payload,
  });

  factory V2ChangeEvent.fromJson(Map<String, dynamic> json) {
    return V2ChangeEvent(
      token: (json['token'] as num?)?.toInt() ?? 0,
      op: json['op'] as String? ?? '',
      entityType: json['entityType'] as String? ?? '',
      entityId: json['entityId'] as String? ?? '',
      payload: json['payload'] is Map
          ? Map<String, dynamic>.from(json['payload'] as Map)
          : null,
    );
  }

  final int token;

  /// `upsert` or `delete`.
  final String op;

  /// `album`, `song`, `playlist`, `playlist_song` or `artwork`.
  final String entityType;
  final String entityId;

  /// Entity JSON matching the corresponding `/v2` list item shape; null for
  /// deletes (and, defensively, for upserts a future server chooses not to
  /// inline — treated as "full resync required", matching mobile).
  final Map<String, dynamic>? payload;

  bool get isUpsert => op == 'upsert';
  bool get isDelete => op == 'delete';
}

class V2ChangesPage {
  V2ChangesPage({
    required this.fromToken,
    required this.toToken,
    required this.syncToken,
    required this.hasMore,
    required this.events,
  });

  factory V2ChangesPage.fromJson(Map<String, dynamic> json) {
    return V2ChangesPage(
      fromToken: (json['fromToken'] as num?)?.toInt() ?? 0,
      toToken: (json['toToken'] as num?)?.toInt() ?? 0,
      syncToken: (json['syncToken'] as num?)?.toInt() ?? 0,
      hasMore: json['hasMore'] as bool? ?? false,
      events: (json['events'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map(
              (item) => V2ChangeEvent.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false),
    );
  }

  final int fromToken;
  final int toToken;

  /// The server's latest catalog token at response time.
  final int syncToken;
  final bool hasMore;
  final List<V2ChangeEvent> events;
}

/// One page of the server's `/v2/bootstrap` feed: an interleaved slice of
/// the full catalog plus the sync token to resume `/v2/changes` from.
class V2BootstrapPage {
  V2BootstrapPage({
    required this.syncToken,
    required this.albums,
    required this.songs,
    required this.playlists,
    required this.nextCursor,
    required this.hasMore,
  });

  factory V2BootstrapPage.fromJson(Map<String, dynamic> json) {
    final pageInfo =
        json['pageInfo'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    return V2BootstrapPage(
      syncToken: (json['syncToken'] as num?)?.toInt() ?? 0,
      albums: (json['albums'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(Album.fromJson)
          .toList(growable: false),
      songs: (json['songs'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(Track.fromJson)
          .toList(growable: false),
      playlists: (json['playlists'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(PlaylistSummary.fromJson)
          .toList(growable: false),
      nextCursor: pageInfo['nextCursor'] as String?,
      hasMore: pageInfo['hasMore'] as bool? ?? false,
    );
  }

  final int syncToken;
  final List<Album> albums;
  final List<Track> songs;
  final List<PlaylistSummary> playlists;
  final String? nextCursor;
  final bool hasMore;
}
