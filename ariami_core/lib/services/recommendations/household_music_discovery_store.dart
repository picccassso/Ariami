import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../utils/secure_file_permissions.dart';
import 'music_discovery_api_key_config.dart';

/// Persists the household Last.fm API key beside Ariami's account data.
///
/// Last.fm API keys are public application identifiers, but the file still
/// receives owner-only permissions because it is household configuration.
/// Ariami never stores the separate Last.fm API secret here.
class HouseholdMusicDiscoveryStore {
  static const int maxApiKeyBytes = MusicDiscoveryApiKeyConfig.maxApiKeyBytes;

  HouseholdMusicDiscoveryStore({required this.filePath});

  final String filePath;

  bool _initialized = false;
  String? _lastFmApiKey;
  Future<void> _mutationQueue = Future<void>.value();

  bool get isInitialized => _initialized;

  String? get lastFmApiKey {
    _ensureInitialized();
    return _lastFmApiKey;
  }

  /// Loads existing configuration. Missing, malformed, and oversized files
  /// start empty so a damaged optional setting cannot block server startup.
  void initialize() {
    if (_initialized) return;
    try {
      final file = File(filePath);
      if (file.existsSync()) {
        final decoded = jsonDecode(file.readAsStringSync());
        if (decoded is Map<String, dynamic>) {
          _lastFmApiKey = normalizeApiKey(decoded['lastFmApiKey']);
        }
      }
    } catch (_) {
      _lastFmApiKey = null;
    }
    _initialized = true;
  }

  /// Stores a trimmed, non-empty API key. Mutations are serialized so the
  /// last completed request is also the value left on disk.
  Future<void> save(String value) {
    _ensureInitialized();
    final normalized = normalizeApiKey(value);
    if (normalized == null) {
      throw ArgumentError('Last.fm API key is empty or too large');
    }
    return _enqueueMutation(normalized);
  }

  /// Stores [value] only while the household has no key. This makes automatic
  /// client migration deterministic when two owner devices reconnect at once.
  Future<bool> saveIfEmpty(String value) async {
    _ensureInitialized();
    final normalized = normalizeApiKey(value);
    if (normalized == null) {
      throw ArgumentError('Last.fm API key is empty or too large');
    }
    var saved = false;
    _mutationQueue = _mutationQueue.catchError((_) {}).then((_) async {
      if (_lastFmApiKey != null) return;
      await _persistValue(normalized);
      _lastFmApiKey = normalized;
      saved = true;
    });
    await _mutationQueue;
    return saved;
  }

  Future<void> clear() {
    _ensureInitialized();
    return _enqueueMutation(null);
  }

  void close() {
    _initialized = false;
    _lastFmApiKey = null;
    _mutationQueue = Future<void>.value();
  }

  static String? normalizeApiKey(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim();
    if (normalized.isEmpty || utf8.encode(normalized).length > maxApiKeyBytes) {
      return null;
    }
    return normalized;
  }

  Future<void> _enqueueMutation(String? value) {
    _mutationQueue = _mutationQueue.catchError((_) {}).then((_) async {
      final file = File(filePath);
      if (value == null) {
        if (await file.exists()) await file.delete();
        _lastFmApiKey = null;
        return;
      }
      await _persistValue(value);
      _lastFmApiKey = value;
    });
    return _mutationQueue;
  }

  Future<void> _persistValue(String value) async {
    final file = File(filePath);
    final directory = file.parent;
    if (!await directory.exists()) await directory.create(recursive: true);
    await SecureFilePermissions.restrictDirectory(directory.path);
    final tempFile = File('$filePath.tmp');
    await tempFile.writeAsString(jsonEncode(<String, dynamic>{
      'schemaVersion': 1,
      'lastFmApiKey': value,
    }));
    await SecureFilePermissions.restrictFile(tempFile.path);
    await tempFile.rename(filePath);
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
        'HouseholdMusicDiscoveryStore not initialized. Call initialize() first.',
      );
    }
  }
}
