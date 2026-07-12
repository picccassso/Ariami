import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../utils/secure_file_permissions.dart';

/// Persists a small set of opaque, client-verified license files.
///
/// Client apps store household license files on the server so every device
/// can fetch them over the API. The server is a relay only: it never
/// parses, validates, or otherwise inspects the contents — clients verify
/// the files themselves. Holding more than one file lets households whose
/// apps were bought separately (each app uploading its own file) coexist:
/// each device fetches the whole set and picks the file that verifies for
/// it.
class LicenseFileStore {
  /// Uploads beyond this are rejected before touching disk.
  static const int maxLicenseFileBytes = 8 * 1024;

  /// Distinct files kept; storing beyond this evicts the oldest.
  static const int maxLicenseFiles = 4;

  final String filePath;

  bool _initialized = false;
  final List<String> _licenseFiles = [];
  Future<void> _persistQueue = Future.value();

  LicenseFileStore({required this.filePath});

  bool get isInitialized => _initialized;

  /// Loads any previously stored license files from disk. Never throws on a
  /// missing or unreadable file — the store just starts empty. Understands
  /// both the current JSON layout and the original single-file layout
  /// (raw contents).
  void initialize() {
    if (_initialized) return;
    try {
      final file = File(filePath);
      if (file.existsSync()) {
        _loadFromContents(file.readAsStringSync());
      }
    } catch (_) {
      // Start empty; a client re-upload restores the files.
    }
    _initialized = true;
  }

  void _loadFromContents(String contents) {
    if (contents.trim().isEmpty) return;
    Object? decoded;
    try {
      decoded = jsonDecode(contents);
    } catch (_) {
      decoded = null;
    }
    if (decoded is Map<String, dynamic> && decoded['files'] is List) {
      for (final entry in decoded['files'] as List) {
        if (entry is String && _acceptable(entry)) {
          _addInMemory(entry);
        }
      }
      return;
    }
    // Legacy layout: the file held a single license file verbatim.
    if (utf8.encode(contents).length <= maxLicenseFileBytes) {
      _licenseFiles.add(contents);
    }
  }

  bool _acceptable(String licenseFile) =>
      licenseFile.trim().isNotEmpty &&
      utf8.encode(licenseFile).length <= maxLicenseFileBytes;

  void _addInMemory(String licenseFile) {
    // Re-storing an existing file refreshes it to "newest" so the legacy
    // single-file `licenseFile` accessor keeps returning it.
    _licenseFiles.remove(licenseFile);
    _licenseFiles.add(licenseFile);
    while (_licenseFiles.length > maxLicenseFiles) {
      _licenseFiles.removeAt(0);
    }
  }

  /// All stored license files, oldest first.
  List<String> get licenseFiles {
    _ensureInitialized();
    return List.unmodifiable(_licenseFiles);
  }

  /// The most recently stored license file, or null when none has been
  /// uploaded. Kept for clients that predate multi-file storage.
  String? get licenseFile {
    _ensureInitialized();
    return _licenseFiles.isEmpty ? null : _licenseFiles.last;
  }

  /// Stores [licenseFile] verbatim alongside any other stored files
  /// (replacing an identical copy, evicting the oldest beyond
  /// [maxLicenseFiles]). Throws [ArgumentError] when empty or over
  /// [maxLicenseFileBytes].
  Future<void> save(String licenseFile) async {
    _ensureInitialized();
    if (!_acceptable(licenseFile)) {
      throw ArgumentError('License file is empty or too large');
    }
    _addInMemory(licenseFile);
    return _persist();
  }

  /// Removes all stored license files.
  Future<void> clear() async {
    _ensureInitialized();
    _licenseFiles.clear();
    return _persist();
  }

  void close() {
    _initialized = false;
    _licenseFiles.clear();
  }

  /// Atomic write (temp file + rename) with owner-only permissions, like
  /// the other account-data stores kept beside the auth files.
  Future<void> _persist() {
    final snapshot = List<String>.from(_licenseFiles);
    _persistQueue = _persistQueue.catchError((_) {}).then((_) async {
      final file = File(filePath);
      if (snapshot.isEmpty) {
        if (await file.exists()) {
          await file.delete();
        }
        return;
      }
      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await SecureFilePermissions.restrictDirectory(dir.path);
      final tempFile = File('$filePath.tmp');
      await tempFile.writeAsString(jsonEncode({'files': snapshot}));
      await SecureFilePermissions.restrictFile(tempFile.path);
      await tempFile.rename(filePath);
    });
    return _persistQueue;
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
        'LicenseFileStore not initialized. Call initialize() first.',
      );
    }
  }
}
