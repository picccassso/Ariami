import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Persists user-chosen device display names, keyed by device ID.
///
/// Clients keep reporting their built-in default name ("Android Device",
/// "Ariami Desktop", ...) when they identify; the server overlays these
/// custom names on top so a rename survives reconnects and server restarts
/// and is seen identically by every client of the household.
class DeviceNameStore {
  final Map<String, String> _names = {};

  String? _filePath;
  bool _initialized = false;

  /// Serialize persist operations to avoid temp-file rename collisions
  Future<void> _persistQueue = Future.value();

  bool get isInitialized => _initialized;

  /// Load names from the JSON file at [filePath] (created on first write).
  Future<void> initialize(String filePath) async {
    if (_initialized) return;

    _filePath = filePath;
    final file = File(filePath);

    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final jsonData = jsonDecode(content);
          if (jsonData is Map<String, dynamic>) {
            final names = jsonData['names'];
            if (names is Map<String, dynamic>) {
              for (final entry in names.entries) {
                final value = entry.value;
                if (value is String && value.isNotEmpty) {
                  _names[entry.key] = value;
                }
              }
            }
          }
        }
      } catch (e) {
        // If file is corrupted, start fresh but log the error
        print('DeviceNameStore: Error loading device_names.json: $e');
        _names.clear();
      }
    }

    _initialized = true;
  }

  /// The custom display name for [deviceId], or null when the device keeps
  /// its client-reported default.
  String? nameFor(String deviceId) => _names[deviceId];

  /// Set (or replace) the custom display name for [deviceId].
  Future<void> setName(String deviceId, String name) async {
    _ensureInitialized();
    if (_names[deviceId] == name) return;
    _names[deviceId] = name;
    await _persist();
  }

  /// Persist the current state to the JSON file.
  /// Uses atomic write (write to temp, then rename) for safety.
  Future<void> _persist() async {
    if (_filePath == null) return;

    _persistQueue = _persistQueue.catchError((_) {}).then((_) async {
      final file = File(_filePath!);
      final tempFile = File('${_filePath!}.tmp');

      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final jsonString = jsonEncode({
        'names': _names,
        'lastModified': DateTime.now().toUtc().toIso8601String(),
      });

      await tempFile.writeAsString(jsonString);
      await tempFile.rename(_filePath!);
    });

    return _persistQueue;
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
          'DeviceNameStore not initialized. Call initialize() first.');
    }
  }

  /// Testing-only helper to clear in-memory state between test runs.
  void resetForTesting() {
    _names.clear();
    _filePath = null;
    _initialized = false;
    _persistQueue = Future.value();
  }
}
