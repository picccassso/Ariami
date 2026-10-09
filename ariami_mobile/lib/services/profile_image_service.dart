import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../utils/image_decode.dart';

/// Service for managing the local profile image.
///
/// The image is stored locally and is cleared when the user logs out.
/// This service uses the singleton pattern and extends ChangeNotifier
/// to allow widgets to rebuild when the image changes.
class ProfileImageService extends ChangeNotifier {
  static final ProfileImageService _instance = ProfileImageService._internal();
  factory ProfileImageService() => _instance;
  ProfileImageService._internal();

  static const String _profileImageFileName = 'profile_image';

  String? _imagePath;
  bool _initialized = false;

  /// Cached provider instance so the image is decoded once and reused across
  /// rebuilds (e.g. every time the Settings tab is re-entered) instead of being
  /// re-read from the device each time.
  ImageProvider? _cachedProvider;

  ImageProvider? get imageProvider {
    if (_imagePath == null) return null;
    final file = File(_imagePath!);
    if (!file.existsSync()) {
      _imagePath = null;
      _cachedProvider = null;
      return null;
    }
    return _cachedProvider ??= avatarImage(FileImage(file));
  }

  /// Point the service at [imagePath] (or clear it when null), rebuild the
  /// cached provider, and warm Flutter's global image cache so subsequent reads
  /// resolve synchronously without touching disk.
  void _setImagePath(String? imagePath) {
    // Evict any previously cached bytes so a replacement photo written to the
    // same path (e.g. same file extension) isn't served stale from the cache.
    _cachedProvider?.evict();

    _imagePath = imagePath;
    _cachedProvider =
        imagePath != null ? avatarImage(FileImage(File(imagePath))) : null;
    if (_cachedProvider != null) {
      _cachedProvider!.evict();
      _precache(_cachedProvider!);
    }
  }

  /// Force [provider] to decode and remain in the global image cache without
  /// needing a BuildContext.
  void _precache(ImageProvider provider) {
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (_, __) => stream.removeListener(listener),
      onError: (_, __) => stream.removeListener(listener),
    );
    stream.addListener(listener);
  }

  String? get imagePath => _imagePath;

  bool get hasImage => _imagePath != null && File(_imagePath!).existsSync();

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final appDir = await getApplicationDocumentsDirectory();
    final profileDir = Directory('${appDir.path}/profile');

    if (!await profileDir.exists()) {
      return;
    }

    final files = await profileDir.list().toList();
    for (final file in files) {
      if (file is File && path.basenameWithoutExtension(file.path) == _profileImageFileName) {
        _setImagePath(file.path);
        notifyListeners();
        return;
      }
    }
  }

  Future<void> _deleteExistingImage(Directory profileDir) async {
    if (!await profileDir.exists()) return;

    final files = await profileDir.list().toList();
    for (final file in files) {
      if (file is File && path.basenameWithoutExtension(file.path) == _profileImageFileName) {
        await file.delete();
      }
    }
  }

  /// Save raw [bytes] as the profile image. Used to mirror the account's
  /// server-side avatar so screens that show the local photo (e.g. the
  /// Settings header) stay in sync with it.
  Future<void> setImageBytes(List<int> bytes, {required String extension}) async {
    final appDir = await getApplicationDocumentsDirectory();
    final profileDir = Directory('${appDir.path}/profile');

    if (!await profileDir.exists()) {
      await profileDir.create(recursive: true);
    }

    await _deleteExistingImage(profileDir);

    final destPath = '${profileDir.path}/$_profileImageFileName.$extension';
    await File(destPath).writeAsBytes(bytes, flush: true);

    _setImagePath(destPath);
    notifyListeners();
  }

  Future<void> removeImage() async {
    if (_imagePath == null) return;

    final file = File(_imagePath!);
    if (await file.exists()) {
      await file.delete();
    }

    _setImagePath(null);
    notifyListeners();
  }

  Future<void> clear() async {
    final appDir = await getApplicationDocumentsDirectory();
    final profileDir = Directory('${appDir.path}/profile');

    if (await profileDir.exists()) {
      await profileDir.delete(recursive: true);
    }

    _imagePath = null;
    _initialized = false;
    notifyListeners();
  }
}
