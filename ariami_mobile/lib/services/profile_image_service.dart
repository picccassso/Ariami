import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

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

  /// Get the current profile image as an ImageProvider, or null if no image is set
  ImageProvider? get imageProvider {
    if (_imagePath == null) return null;
    final file = File(_imagePath!);
    if (!file.existsSync()) {
      _imagePath = null;
      return null;
    }
    return FileImage(file);
  }

  /// Get the current image path, or null if no image is set
  String? get imagePath => _imagePath;

  /// Check if a profile image is set
  bool get hasImage => _imagePath != null && File(_imagePath!).existsSync();

  /// Initialize the service by loading any existing profile image
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final appDir = await getApplicationDocumentsDirectory();
    final profileDir = Directory('${appDir.path}/profile');

    if (!await profileDir.exists()) {
      return;
    }

    // Look for existing profile image (any extension)
    final files = await profileDir.list().toList();
    for (final file in files) {
      if (file is File && path.basenameWithoutExtension(file.path) == _profileImageFileName) {
        _imagePath = file.path;
        notifyListeners();
        return;
      }
    }
  }

  /// Pick a new profile image using the file picker
  /// Returns true if an image was selected, false otherwise
  Future<bool> pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) {
      return false;
    }

    final pickedPath = result.files.first.path;
    if (pickedPath == null) {
      return false;
    }

    await _saveImage(pickedPath);
    return true;
  }

  /// Save an image from a given path as the profile image
  Future<void> _saveImage(String sourcePath) async {
    final appDir = await getApplicationDocumentsDirectory();
    final profileDir = Directory('${appDir.path}/profile');

    // Create profile directory if it doesn't exist
    if (!await profileDir.exists()) {
      await profileDir.create(recursive: true);
    }

    // Delete existing profile image if any
    await _deleteExistingImage(profileDir);

    // Copy the new image
    final ext = path.extension(sourcePath);
    final destPath = '${profileDir.path}/$_profileImageFileName$ext';
    await File(sourcePath).copy(destPath);

    _imagePath = destPath;
    notifyListeners();
  }

  /// Delete existing profile image files
  Future<void> _deleteExistingImage(Directory profileDir) async {
    if (!await profileDir.exists()) return;

    final files = await profileDir.list().toList();
    for (final file in files) {
      if (file is File && path.basenameWithoutExtension(file.path) == _profileImageFileName) {
        await file.delete();
      }
    }
  }

  /// Remove the current profile image
  Future<void> removeImage() async {
    if (_imagePath == null) return;

    final file = File(_imagePath!);
    if (await file.exists()) {
      await file.delete();
    }

    _imagePath = null;
    notifyListeners();
  }

  /// Clear the profile image (called on logout)
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
