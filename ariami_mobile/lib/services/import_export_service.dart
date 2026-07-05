import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/api_models.dart';
import '../models/song_stats.dart';
import '../database/stats_database.dart';
import 'api/connection_service.dart';
import 'library/library_pin_storage.dart';
import 'library/library_repository.dart';
import 'playlist_service.dart';
import 'song_id_remapping_service.dart';
import 'stats/account_stats_service.dart';
import 'stats/streaming_stats_service.dart';

/// Mode for importing data
enum ImportMode { merge, replace }

/// Result of an export operation
class ExportResult {
  final bool success;
  final String? filePath;
  final String? error;
  final int playlistCount;
  final int statsCount;

  ExportResult({
    required this.success,
    this.filePath,
    this.error,
    this.playlistCount = 0,
    this.statsCount = 0,
  });
}

/// Result of an import operation
class ImportResult {
  final bool success;
  final String? error;
  final int playlistsImported;
  final int statsImported;

  ImportResult({
    required this.success,
    this.error,
    this.playlistsImported = 0,
    this.statsImported = 0,
  });
}

/// Service for exporting and importing playlists and streaming stats
class ImportExportService {
  static final ImportExportService _instance = ImportExportService._internal();
  factory ImportExportService() => _instance;
  ImportExportService._internal();

  final PlaylistService _playlistService = PlaylistService();
  final StreamingStatsService _statsService = StreamingStatsService();
  final ConnectionService _connectionService = ConnectionService();
  static const MethodChannel _filePickerChannel = MethodChannel(
    'miguelruivo.flutter.plugins.filepicker',
    StandardMethodCodec(),
  );
  late StatsDatabase _statsDatabase;
  bool _initialized = false;

  /// v4 moves pins to the authenticated account on the server.
  static const int _dataVersion = 4;

  /// Keys for SharedPreferences
  static const String _lastExportKey = 'import_export_last_export';
  static const String _lastImportKey = 'import_export_last_import';

  /// Last export/import timestamps
  DateTime? _lastExportTime;
  DateTime? _lastImportTime;

  DateTime? get lastExportTime => _lastExportTime;
  DateTime? get lastImportTime => _lastImportTime;

  /// Initialize the service
  Future<void> initialize() async {
    if (_initialized) return;
    _statsDatabase = await StatsDatabase.create();

    // Load timestamps from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final exportTimeStr = prefs.getString(_lastExportKey);
    final importTimeStr = prefs.getString(_lastImportKey);

    if (exportTimeStr != null) {
      _lastExportTime = DateTime.tryParse(exportTimeStr);
    }
    if (importTimeStr != null) {
      _lastImportTime = DateTime.tryParse(importTimeStr);
    }

    _initialized = true;
  }

  /// Export playlists and stats to a JSON file with the system document saver.
  Future<ExportResult> exportData() async {
    try {
      await initialize();

      // Ensure playlists are loaded
      await _playlistService.loadPlaylists();

      final exportData = await buildBackupData();

      // Generate filename with timestamp
      final now = DateTime.now();
      final timestamp =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';
      final filename = 'ariami_backup_$timestamp.json';

      // Convert to JSON string
      final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);
      final bytes = utf8.encode(jsonString);

      final savedPath = await _saveBackupFile(
        filename: filename,
        bytes: Uint8List.fromList(bytes),
      );
      if (savedPath == null) {
        return ExportResult(
          success: false,
          error: 'Save cancelled',
        );
      }

      // Save export timestamp
      _lastExportTime = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastExportKey, _lastExportTime!.toIso8601String());

      final playlists = exportData['playlists'] as List<dynamic>;
      final stats = exportData['stats'] as List<dynamic>;

      return ExportResult(
        success: true,
        filePath: savedPath,
        playlistCount: playlists.length,
        statsCount: stats.length,
      );
    } catch (e) {
      print('[ImportExportService] Export error: $e');
      return ExportResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Import data from a JSON file
  Future<ImportResult> importData(ImportMode mode) async {
    try {
      await initialize();

      // Pick a JSON file
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        // The backup JSON is tiny and path may be null for document-provider
        // picks, so eager bytes are the reliable import signal here.
        // ignore: deprecated_member_use
        allowMultiple: false,
        // ignore: deprecated_member_use
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return ImportResult(
          success: false,
          error: 'No file selected',
        );
      }

      final jsonString = await _readPickedBackup(result.files.single);

      final Map<String, dynamic> data;
      try {
        data = json.decode(jsonString) as Map<String, dynamic>;
      } catch (e) {
        return ImportResult(
          success: false,
          error: 'Invalid JSON format',
        );
      }

      return importBackupData(data, mode);
    } catch (e) {
      print('[ImportExportService] Import error: $e');
      return ImportResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  Future<String?> _saveBackupFile({
    required String filename,
    required Uint8List bytes,
  }) {
    // Use the native file-picker save method directly. FilePicker.saveFile()
    // opens the same system document picker, but its Dart wrapper may try to
    // write again through Android's returned document URI path after the native
    // side has already saved the bytes.
    return _filePickerChannel.invokeMethod<String>('save', {
      'fileName': filename,
      'fileType': FileType.custom.name,
      'initialDirectory': null,
      'allowedExtensions': ['json'],
      'bytes': bytes,
    });
  }

  Future<String> _readPickedBackup(PlatformFile pickedFile) async {
    // ignore: deprecated_member_use
    final bytes = pickedFile.bytes;
    if (bytes != null) {
      return utf8.decode(bytes);
    }

    final path = pickedFile.path;
    if (path != null) {
      return File(path).readAsString();
    }

    throw const FileSystemException(
      'Selected backup could not be read',
    );
  }

  /// Build backup payload for export or testing.
  @visibleForTesting
  Future<Map<String, dynamic>> buildBackupData() async {
    await initialize();
    await _playlistService.loadPlaylists();

    final playlists = _playlistService.playlists;
    final stats = await _statsDatabase.getAllStats();
    final client = _connectionService.apiClient;
    final pinnedItems = client != null && _connectionService.isAuthenticated
        ? await client.getPins()
        : (await LibraryPinStorage.loadForUser(_connectionService.userId))
            .toList();
    final packageInfo = await PackageInfo.fromPlatform();

    return {
      'exportDate': DateTime.now().toIso8601String(),
      'appVersion': packageInfo.version,
      'dataVersion': _dataVersion,
      'schemaVersion': _dataVersion,
      'exportVersion': _dataVersion,
      'playlists': playlists.map((p) => p.toJson()).toList(),
      'stats': stats.map((s) => s.toJson()).toList(),
      'pinnedItems': pinnedItems,
      'hiddenServerPlaylistIds':
          _playlistService.hiddenServerPlaylistIds.toList(),
      'importedFromServer': _playlistService.importedFromServer,
    };
  }

  /// Import backup data from a parsed JSON map (used by tests and [importData]).
  @visibleForTesting
  Future<ImportResult> importBackupData(
    Map<String, dynamic> data,
    ImportMode mode,
  ) async {
    try {
      await initialize();
      await _playlistService.loadPlaylists();

      // Validate structure
      if (!data.containsKey('playlists') || !data.containsKey('stats')) {
        return ImportResult(
          success: false,
          error: 'Invalid backup file format',
        );
      }

      // Check data version for future compatibility
      final dataVersion = data['dataVersion'] as int? ?? 1;
      if (dataVersion > _dataVersion) {
        return ImportResult(
          success: false,
          error: 'Backup was created with a newer app version',
        );
      }

      // Parse playlists
      final playlistsJson = data['playlists'] as List<dynamic>;
      final playlists = playlistsJson
          .map((p) => PlaylistModel.fromJson(p as Map<String, dynamic>))
          .toList();

      // Parse stats
      final statsJson = data['stats'] as List<dynamic>;
      final stats = statsJson
          .map((s) => SongStats.fromJson(s as Map<String, dynamic>))
          .toList();

      // Parse pinned items (v2+, empty for v1 backups)
      final importedPinsRaw =
          data['pinnedItems'] as List<dynamic>? ?? const <dynamic>[];
      final importedPinnedItems = <String>{};
      final importedPinObjects = <dynamic>[];
      for (final raw in importedPinsRaw) {
        if (raw is String) {
          final separator = raw.indexOf(':');
          if (separator <= 0 || separator >= raw.length - 1) continue;
          importedPinnedItems.add(raw);
          importedPinObjects.add(raw);
        } else if (raw is Map) {
          final pin = Map<String, dynamic>.from(raw);
          final type = pin['type'];
          final targetId = pin['targetId'];
          if (type is! String || targetId is! String) continue;
          importedPinnedItems.add('$type:$targetId');
          importedPinObjects.add(pin);
        }
      }

      // Parse server-import state (v3+, empty for older backups)
      final importedHiddenServerPlaylistIds =
          (data['hiddenServerPlaylistIds'] as List<dynamic>?)
                  ?.cast<String>()
                  .toSet() ??
              <String>{};
      final importedFromServerRaw =
          data['importedFromServer'] as Map<String, dynamic>?;
      final importedFromServer = importedFromServerRaw == null
          ? <String, String>{}
          : importedFromServerRaw.map(
              (key, value) => MapEntry(key, value as String),
            );

      // -----------------------------------------------------------------------
      // Remap stale song IDs using current library data
      // -----------------------------------------------------------------------
      List<SongModel> librarySongs = [];
      try {
        final libraryRepo = LibraryRepository();
        librarySongs = await libraryRepo.getSongs();
      } catch (e) {
        print(
            '[ImportExportService] Could not load local library for remapping: $e');
        try {
          if (_connectionService.apiClient != null) {
            librarySongs =
                await _connectionService.libraryReadFacade.getSongs();
          }
        } catch (e2) {
          print(
              '[ImportExportService] Could not fetch library from server for remapping: $e2');
        }
      }

      final remappingService = SongIdRemappingService();
      final remappedPlaylists =
          remappingService.remapPlaylists(playlists, librarySongs);
      final remappedStats = remappingService.remapStats(stats, librarySongs);

      // -----------------------------------------------------------------------
      // Import based on mode
      // -----------------------------------------------------------------------
      int playlistsImported = 0;
      int statsImported = 0;

      final prefs = await SharedPreferences.getInstance();

      if (mode == ImportMode.replace) {
        await _playlistService.replaceAllPlaylists(remappedPlaylists);
        playlistsImported = remappedPlaylists.length;

        await _statsDatabase.resetAllStats();
        if (remappedStats.isNotEmpty) {
          await _statsDatabase.saveAllStats(remappedStats);
        }
        statsImported = remappedStats.length;

        // Replace pinned items
        await LibraryPinStorage.saveForUser(
          _connectionService.userId,
          importedPinnedItems,
        );
      } else {
        playlistsImported =
            await _playlistService.importPlaylists(remappedPlaylists);

        if (remappedStats.isNotEmpty) {
          await _statsDatabase.saveAllStats(remappedStats);
        }
        statsImported = remappedStats.length;

        // Merge pinned items (union with existing)
        if (importedPinnedItems.isNotEmpty) {
          final existing =
              await LibraryPinStorage.loadForUser(_connectionService.userId);
          final merged = existing.union(importedPinnedItems);
          await LibraryPinStorage.saveForUser(
              _connectionService.userId, merged);
        }
      }

      await _playlistService.applyServerImportState(
        hiddenServerPlaylistIds: importedHiddenServerPlaylistIds,
        importedFromServer: importedFromServer,
        replace: mode == ImportMode.replace,
      );

      // Restore pins to the authenticated account. The server owns identity,
      // validates types, preserves sortOrder, and deduplicates repeated files.
      final client = _connectionService.apiClient;
      if (client != null && _connectionService.isAuthenticated) {
        final serverPins = await client.importPins(
          importedPinObjects,
          replace: mode == ImportMode.replace,
        );
        final serverKeys = serverPins
            .where((pin) => pin['type'] is String && pin['targetId'] is String)
            .map((pin) => '${pin['type']}:${pin['targetId']}')
            .toSet();
        await LibraryPinStorage.saveForUser(
          _connectionService.userId,
          serverKeys,
        );
      }

      // Refresh stats service cache
      await _statsService.reloadFromDatabase();

      // Stats from a backup made under a different library path arrive with
      // stale songIds. Above we already remapped the imported rows; this
      // additional pass cleans up stale rows that pre-dated the import (e.g.
      // when the user is importing into a library they never synced after a
      // path move) and merges any rows that now share an id, so artist and
      // album aggregations don't double-count plays for the same song.
      if (librarySongs.isNotEmpty) {
        await _statsService.remapStaleStatIdsFromLibrary(librarySongs);
      }

      // The imported history must also reach the account on the server: show
      // the local view immediately and re-upload this device's baseline (the
      // server replaces the previous baseline per song, so re-imports never
      // stack). Offline imports upload on the next connection.
      await AccountStatsService().resyncBaselineAfterImport();

      // Save import timestamp
      _lastImportTime = DateTime.now();
      await prefs.setString(_lastImportKey, _lastImportTime!.toIso8601String());

      return ImportResult(
        success: true,
        playlistsImported: playlistsImported,
        statsImported: statsImported,
      );
    } catch (e) {
      print('[ImportExportService] Import error: $e');
      return ImportResult(
        success: false,
        error: e.toString(),
      );
    }
  }
}
