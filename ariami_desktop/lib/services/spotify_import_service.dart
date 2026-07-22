import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/models/library_structure.dart';
import 'package:ariami_core/services/library/library_playlist_builder.dart';
import 'package:ariami_core/services/server/http_server.dart';
import 'package:ariami_core/services/stats/spotify_import/library_track_matcher.dart';
import 'package:ariami_core/services/stats/spotify_import/spotify_import_models.dart';
import 'package:ariami_core/services/stats/spotify_import/spotify_importer.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'dashboard_admin_api_service.dart';

class DesktopSpotifyImportFailure implements Exception {
  const DesktopSpotifyImportFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class DesktopSpotifyImportPreview {
  const DesktopSpotifyImportPreview({
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

class DesktopSpotifyImportUploadResult {
  const DesktopSpotifyImportUploadResult({
    required this.accepted,
    required this.duplicates,
    required this.rejected,
  });

  final int accepted;
  final int duplicates;
  final int rejected;
}

/// Native Spotify-history import for the owner-authorized Desktop dashboard.
class DesktopSpotifyImportService {
  DesktopSpotifyImportService({
    required AriamiHttpServer httpServer,
    required DashboardAdminApiService adminApi,
  })  : _httpServer = httpServer,
        _adminApi = adminApi;

  static const int uploadBatchSize = 500;

  final AriamiHttpServer _httpServer;
  final DashboardAdminApiService _adminApi;

  static Future<List<Map<String, dynamic>>> readExportFolder(
    String folderPath,
  ) async {
    final files = await Directory(folderPath)
        .list(followLinks: false)
        .where((entity) => entity is File && _isAudioHistoryFile(entity))
        .cast<File>()
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (files.isEmpty) {
      throw const DesktopSpotifyImportFailure(
        'No Spotify history files were found. Choose the folder containing '
        'Streaming_History_Audio_*.json files.',
      );
    }

    final records = <Map<String, dynamic>>[];
    for (final file in files) {
      dynamic decoded;
      try {
        decoded = jsonDecode(await file.readAsString());
      } catch (_) {
        throw DesktopSpotifyImportFailure(
          '${p.basename(file.path)} is not valid JSON.',
        );
      }
      if (decoded is! List) {
        throw DesktopSpotifyImportFailure(
          '${p.basename(file.path)} does not contain a Spotify history list.',
        );
      }
      records.addAll(decoded.whereType<Map>().map(
            (record) => Map<String, dynamic>.from(record),
          ));
    }
    if (records.isEmpty) {
      throw const DesktopSpotifyImportFailure(
        'The Spotify history files in this folder are empty.',
      );
    }
    return records;
  }

  static List<LibraryCatalogEntry> catalogForLibrary(
    LibraryStructure? library,
  ) {
    if (library == null) return const <LibraryCatalogEntry>[];
    return <LibraryCatalogEntry>[
      for (final album in library.albums.values)
        for (final song in album.songs)
          LibraryCatalogEntry(
            songId: defaultGenerateSongId(song.filePath),
            title: song.title ?? p.basenameWithoutExtension(song.filePath),
            artist: song.artist ?? 'Unknown Artist',
            album: album.title,
            albumId: album.id,
            durationMs: song.duration == null ? null : song.duration! * 1000,
          ),
      for (final song in library.standaloneSongs)
        LibraryCatalogEntry(
          songId: defaultGenerateSongId(song.filePath),
          title: song.title ?? p.basenameWithoutExtension(song.filePath),
          artist: song.artist ?? 'Unknown Artist',
          album: null,
          albumId: null,
          durationMs: song.duration == null ? null : song.duration! * 1000,
        ),
    ];
  }

  Future<DesktopSpotifyImportPreview> analyzeFolder(String folderPath) async {
    final username = await _currentUsername();
    final records = await readExportFolder(folderPath);
    final catalog = catalogForLibrary(_httpServer.libraryManager.library);
    if (catalog.isEmpty) {
      throw const DesktopSpotifyImportFailure(
        'Your Ariami library is empty. Scan the library before importing '
        'Spotify stats.',
      );
    }

    final result = await compute(
      _runDesktopSpotifyImport,
      _DesktopSpotifyImportWork(
        records: records,
        catalog: catalog,
        username: username,
      ),
      debugLabel: 'Desktop server Spotify stats import',
    );
    if (result.events.isEmpty) {
      throw const DesktopSpotifyImportFailure(
        'No eligible audio plays were found in this Spotify export.',
      );
    }
    return DesktopSpotifyImportPreview(
      accountUsername: username,
      result: result,
    );
  }

  Future<DesktopSpotifyImportUploadResult> upload(
    DesktopSpotifyImportPreview preview, {
    void Function(int sent, int total)? onProgress,
  }) async {
    if (await _currentUsername() != preview.accountUsername) {
      throw const DesktopSpotifyImportFailure(
        'The signed-in owner changed. Start the import again.',
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
      final response = await _adminApi.sendAuthenticatedRequest(
        method: 'POST',
        path: '/api/v2/listening/events',
        body: <String, dynamic>{
          'events': events
              .sublist(start, end)
              .map((event) => event.toJson())
              .toList(),
        },
      );
      if (response == null || !response.isSuccess) {
        final detail = response?.statusCode == 404
            ? 'Update Ariami before importing Spotify stats.'
            : 'Upload failed on batch $batchNumber. Plays already uploaded '
                'are saved; retrying is safe.';
        throw DesktopSpotifyImportFailure(detail);
      }
      accepted += response.jsonBody?['accepted'] as int? ?? 0;
      duplicates += response.jsonBody?['duplicates'] as int? ?? 0;
      rejected += response.jsonBody?['rejected'] as int? ?? 0;
      onProgress?.call(end, events.length);
    }

    return DesktopSpotifyImportUploadResult(
      accepted: accepted,
      duplicates: duplicates,
      rejected: rejected,
    );
  }

  Future<String> _currentUsername() async {
    final response = await _adminApi.sendAuthenticatedRequest(
      method: 'GET',
      path: '/api/me',
    );
    final username = response?.jsonBody?['username'] as String?;
    if (response == null ||
        !response.isSuccess ||
        username == null ||
        username.trim().isEmpty) {
      throw const DesktopSpotifyImportFailure(
        'The owner account could not be confirmed. Sign in again and restart '
        'the import.',
      );
    }
    return username.trim();
  }

  static bool _isAudioHistoryFile(FileSystemEntity entity) {
    final name = p.basename(entity.path);
    return name.startsWith('Streaming_History_Audio_') &&
        name.endsWith('.json');
  }
}

class _DesktopSpotifyImportWork {
  const _DesktopSpotifyImportWork({
    required this.records,
    required this.catalog,
    required this.username,
  });

  final List<Map<String, dynamic>> records;
  final List<LibraryCatalogEntry> catalog;
  final String username;
}

Future<SpotifyImportResult> _runDesktopSpotifyImport(
  _DesktopSpotifyImportWork work,
) {
  return const SpotifyImporter().run(
    records: work.records,
    matcher: LibraryTrackMatcher(work.catalog),
    tzOffsetMinutesFor: (utcMillis) =>
        DateTime.fromMillisecondsSinceEpoch(utcMillis, isUtc: false)
            .timeZoneOffset
            .inMinutes,
    userId: work.username,
    clientKind: 'desktop-server',
  );
}
