import 'dart:convert';

import 'package:ariami_core/models/api_models.dart';
import 'package:ariami_core/services/stats/spotify_import/library_track_matcher.dart';
import 'package:ariami_core/services/stats/spotify_import/spotify_import_models.dart';
import 'package:ariami_core/services/stats/spotify_import/spotify_importer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import 'web_api_client.dart';

class SpotifyImportFailure implements Exception {
  const SpotifyImportFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class SpotifyImportPreview {
  const SpotifyImportPreview({
    required this.accountUsername,
    required this.result,
  });

  final String accountUsername;
  final SpotifyImportResult result;

  (int matched, int unmatched) get uniqueTrackCounts {
    final matched = <String>{};
    final unmatched = <String>{};
    for (final event in result.events) {
      (event.songId.startsWith('spotify-uri:') ? unmatched : matched)
          .add(event.songId);
    }
    return (matched.length, unmatched.length);
  }
}

class SpotifyImportUploadResult {
  const SpotifyImportUploadResult({
    required this.accepted,
    required this.duplicates,
    required this.rejected,
  });

  final int accepted;
  final int duplicates;
  final int rejected;
}

/// Account-scoped Spotify import workflow for the signed-in CLI dashboard.
class SpotifyImportService {
  SpotifyImportService(this._apiClient);

  static const int uploadBatchSize = 500;

  final WebApiClient _apiClient;

  /// Reads the audio-history JSON files selected by the browser.
  static List<Map<String, dynamic>> decodeSelectedFiles(
    List<PlatformFile> files,
  ) {
    final audioFiles = files.where((file) {
      final name = file.name;
      return name.startsWith('Streaming_History_Audio_') &&
          name.endsWith('.json');
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    if (audioFiles.isEmpty) {
      throw const SpotifyImportFailure(
        'No Spotify audio-history files were selected. Choose the '
        'Streaming_History_Audio_*.json files from your unzipped export.',
      );
    }

    final records = <Map<String, dynamic>>[];
    for (final file in audioFiles) {
      final bytes = file.bytes;
      if (bytes == null) {
        throw SpotifyImportFailure('Could not read ${file.name}.');
      }

      dynamic decoded;
      try {
        decoded = jsonDecode(utf8.decode(bytes));
      } catch (_) {
        throw SpotifyImportFailure('${file.name} is not valid JSON.');
      }
      if (decoded is! List) {
        throw SpotifyImportFailure(
          '${file.name} does not contain a Spotify history list.',
        );
      }
      records.addAll(decoded.whereType<Map>().map(
            (record) => Map<String, dynamic>.from(record),
          ));
    }

    if (records.isEmpty) {
      throw const SpotifyImportFailure(
        'The selected Spotify history files are empty.',
      );
    }
    return records;
  }

  Future<SpotifyImportPreview> analyze(
    List<Map<String, dynamic>> records,
  ) async {
    final username = await _currentUsername();
    final catalog = await _loadCatalog();
    if (catalog.isEmpty) {
      throw const SpotifyImportFailure(
        'Your Ariami library is empty. Scan the library before importing '
        'Spotify stats.',
      );
    }

    final result = await compute(
      _runSpotifyImport,
      _SpotifyImportWork(
        records: records,
        catalog: catalog,
        username: username,
      ),
      debugLabel: 'CLI Spotify stats import',
    );
    if (result.events.isEmpty) {
      throw const SpotifyImportFailure(
        'No eligible audio plays were found in the selected files.',
      );
    }
    return SpotifyImportPreview(accountUsername: username, result: result);
  }

  Future<SpotifyImportUploadResult> upload(
    SpotifyImportPreview preview, {
    void Function(int sent, int total)? onProgress,
  }) async {
    if (await _currentUsername() != preview.accountUsername) {
      throw const SpotifyImportFailure(
        'The signed-in account changed. Start the import again.',
      );
    }

    var accepted = 0;
    var duplicates = 0;
    var rejected = 0;
    final events = preview.result.events;
    var batchNumber = 0;
    for (var start = 0; start < events.length; start += uploadBatchSize) {
      batchNumber++;
      final end = (start + uploadBatchSize).clamp(0, events.length);
      final response = await _apiClient.post(
        '/api/v2/listening/events',
        body: <String, dynamic>{
          'events': events
              .sublist(start, end)
              .map((event) => event.toJson())
              .toList(),
        },
        includeDeviceIdentity: true,
      );
      if (!response.isSuccess) {
        final detail = response.statusCode == 404
            ? 'Update the Ariami server before importing Spotify stats.'
            : 'Upload failed on batch $batchNumber. Plays already uploaded '
                'are saved; retrying is safe.';
        throw SpotifyImportFailure(detail);
      }
      accepted += response.jsonBody?['accepted'] as int? ?? 0;
      duplicates += response.jsonBody?['duplicates'] as int? ?? 0;
      rejected += response.jsonBody?['rejected'] as int? ?? 0;
      onProgress?.call(end, events.length);
    }

    return SpotifyImportUploadResult(
      accepted: accepted,
      duplicates: duplicates,
      rejected: rejected,
    );
  }

  Future<String> _currentUsername() async {
    final response = await _apiClient.get('/api/me');
    final username = response.jsonBody?['username'] as String?;
    if (!response.isSuccess || username == null || username.trim().isEmpty) {
      throw const SpotifyImportFailure(
        'The signed-in account could not be confirmed. Sign in again and '
        'restart the import.',
      );
    }
    return username.trim();
  }

  Future<List<LibraryCatalogEntry>> _loadCatalog() async {
    final albums = <String, AlbumModel>{};
    final songs = <String, SongModel>{};
    String? cursor;

    do {
      final uri = Uri(
        path: '/api/v2/bootstrap',
        queryParameters: <String, String>{
          'limit': '500',
          if (cursor != null) 'cursor': cursor,
        },
      );
      final response = await _apiClient.get(uri.toString());
      if (!response.isSuccess) {
        throw const SpotifyImportFailure(
          'Could not load the Ariami library for matching.',
        );
      }

      final body = response.jsonBody ?? const <String, dynamic>{};
      for (final raw in body['albums'] as List<dynamic>? ?? const []) {
        if (raw is! Map<String, dynamic>) continue;
        final album = AlbumModel.fromJson(raw);
        albums[album.id] = album;
      }
      for (final raw in body['songs'] as List<dynamic>? ?? const []) {
        if (raw is! Map<String, dynamic>) continue;
        final song = SongModel.fromJson(raw);
        songs[song.id] = song;
      }

      final pageInfo = body['pageInfo'];
      if (pageInfo is Map<String, dynamic> && pageInfo['hasMore'] == true) {
        cursor = pageInfo['nextCursor'] as String?;
        if (cursor == null || cursor.isEmpty) {
          throw const SpotifyImportFailure(
            'The Ariami library response ended unexpectedly.',
          );
        }
      } else {
        cursor = null;
      }
    } while (cursor != null);

    return <LibraryCatalogEntry>[
      for (final song in songs.values)
        LibraryCatalogEntry(
          songId: song.id,
          title: song.title,
          artist: song.artist,
          album: song.albumId == null ? null : albums[song.albumId]?.title,
          albumId: song.albumId,
          durationMs: song.duration > 0 ? song.duration * 1000 : null,
        ),
    ];
  }
}

class _SpotifyImportWork {
  const _SpotifyImportWork({
    required this.records,
    required this.catalog,
    required this.username,
  });

  final List<Map<String, dynamic>> records;
  final List<LibraryCatalogEntry> catalog;
  final String username;
}

Future<SpotifyImportResult> _runSpotifyImport(_SpotifyImportWork work) {
  return const SpotifyImporter().run(
    records: work.records,
    matcher: LibraryTrackMatcher(work.catalog),
    tzOffsetMinutesFor: (utcMillis) =>
        DateTime.fromMillisecondsSinceEpoch(utcMillis, isUtc: false)
            .timeZoneOffset
            .inMinutes,
    userId: work.username,
    clientKind: 'cli',
  );
}
