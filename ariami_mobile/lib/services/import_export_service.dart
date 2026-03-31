import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/api_models.dart';
import '../models/song_stats.dart';
import '../database/stats_database.dart';
import 'playlist_service.dart';
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
  late StatsDatabase _statsDatabase;
  bool _initialized = false;

  /// Data version for future compatibility (v2 adds pinnedItems)
  static const int _dataVersion = 2;

  static const String _pinnedItemsKey = 'library_pinned_items';

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

  /// Export playlists and stats to a JSON file and open share sheet
  Future<ExportResult> exportData() async {
    try {
      await initialize();

      // Ensure playlists are loaded
      await _playlistService.loadPlaylists();

      // Get all data
      final playlists = _playlistService.playlists;
      final stats = await _statsDatabase.getAllStats();

      // Get pinned items
      final prefs = await SharedPreferences.getInstance();
      final pinnedJson = prefs.getString(_pinnedItemsKey);
      List<String> pinnedItems = [];
      if (pinnedJson != null && pinnedJson.isNotEmpty) {
        try {
          pinnedItems =
              (jsonDecode(pinnedJson) as List<dynamic>).cast<String>();
        } catch (_) {}
      }

      // Get app version
      final packageInfo = await PackageInfo.fromPlatform();

      final exportData = {
        'exportDate': DateTime.now().toIso8601String(),
        'appVersion': packageInfo.version,
        'dataVersion': _dataVersion,
        'playlists': playlists.map((p) => p.toJson()).toList(),
        'stats': stats.map((s) => s.toJson()).toList(),
        'pinnedItems': pinnedItems,
      };

      // Generate filename with timestamp
      final now = DateTime.now();
      final timestamp = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';
      final filename = 'ariami_backup_$timestamp.json';

      // Convert to JSON string
      final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);
      final bytes = utf8.encode(jsonString);

      // Use file picker to let user choose save location
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Ariami Backup',
        fileName: filename,
        type: FileType.custom,
        allowedExtensions: ['json'],
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
      await prefs.setString(_lastExportKey, _lastExportTime!.toIso8601String());

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
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.isEmpty) {
        return ImportResult(
          success: false,
          error: 'No file selected',
        );
      }

      final file = File(result.files.single.path!);
      final jsonString = await file.readAsString();

      // Parse JSON
      final Map<String, dynamic> data;
      try {
        data = json.decode(jsonString) as Map<String, dynamic>;
      } catch (e) {
        return ImportResult(
          success: false,
          error: 'Invalid JSON format',
        );
      }

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
      final importedPinnedItems = (data['pinnedItems'] as List<dynamic>?)
              ?.cast<String>()
              .toSet() ??
          <String>{};

      // Import based on mode
      int playlistsImported = 0;
      int statsImported = 0;

      final prefs = await SharedPreferences.getInstance();

      if (mode == ImportMode.replace) {
        await _playlistService.replaceAllPlaylists(playlists);
        playlistsImported = playlists.length;

        await _statsDatabase.resetAllStats();
        if (stats.isNotEmpty) {
          await _statsDatabase.saveAllStats(stats);
        }
        statsImported = stats.length;

        // Replace pinned items
        await prefs.setString(
            _pinnedItemsKey, jsonEncode(importedPinnedItems.toList()));
      } else {
        playlistsImported = await _playlistService.importPlaylists(playlists);

        if (stats.isNotEmpty) {
          await _statsDatabase.saveAllStats(stats);
        }
        statsImported = stats.length;

        // Merge pinned items (union with existing)
        if (importedPinnedItems.isNotEmpty) {
          final existingJson = prefs.getString(_pinnedItemsKey);
          Set<String> existing = {};
          if (existingJson != null && existingJson.isNotEmpty) {
            try {
              existing =
                  (jsonDecode(existingJson) as List<dynamic>).cast<String>().toSet();
            } catch (_) {}
          }
          final merged = existing.union(importedPinnedItems);
          await prefs.setString(
              _pinnedItemsKey, jsonEncode(merged.toList()));
        }
      }

      // Refresh stats service cache
      await _statsService.reloadFromDatabase();

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
