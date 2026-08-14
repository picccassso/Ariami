import 'package:ariami_core/services/stats/credited_artist_splitter.dart';
import 'package:flutter/foundation.dart';

import 'api/connection_service.dart';

/// Service managing custom artist photos on mobile and keeping them synced with
/// the server across all devices.
class ArtistImageService extends ChangeNotifier {
  static final ArtistImageService _instance = ArtistImageService._internal();
  factory ArtistImageService() => _instance;
  ArtistImageService._internal();

  /// Normalized artist key -> image version (updatedAt milliseconds).
  final Map<String, int> _artistImageVersions = <String, int>{};

  /// Returns the cache-busting version of an artist's custom image, or null if
  /// none is set.
  int? artistImageVersion(String artistName) =>
      _artistImageVersions[normalizeArtistKey(artistName)];

  /// Fetches the user's custom artist image versions from the server.
  Future<void> loadArtistImages() async {
    final client = ConnectionService().apiClient;
    if (client == null || !ConnectionService().isConnected) return;
    try {
      final versions = await client.getArtistImages();
      _artistImageVersions
        ..clear()
        ..addAll(versions);
      notifyListeners();
    } catch (e) {
      debugPrint('[ArtistImageService] Failed to load artist images: $e');
    }
  }

  /// Uploads or updates a custom photo for [artistName].
  Future<void> putArtistPhoto(
    String artistName,
    Uint8List bytes,
    String contentType,
  ) async {
    final client = ConnectionService().apiClient;
    if (client == null) throw StateError('Not connected to a server.');
    final updatedAt = await client.putArtistImage(
      artistName,
      bytes: bytes,
      contentType: contentType,
    );
    final key = normalizeArtistKey(artistName);
    _artistImageVersions[key] =
        updatedAt ?? DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
  }

  /// Removes the custom photo for [artistName].
  Future<void> deleteArtistPhoto(String artistName) async {
    final client = ConnectionService().apiClient;
    if (client == null) throw StateError('Not connected to a server.');
    await client.deleteArtistImage(artistName);
    final key = normalizeArtistKey(artistName);
    _artistImageVersions.remove(key);
    notifyListeners();
  }

  /// Clears stored artist image versions (on disconnect/logout).
  void clear() {
    _artistImageVersions.clear();
    notifyListeners();
  }

  @visibleForTesting
  void setVersionsForTesting(Map<String, int> versions) {
    _artistImageVersions
      ..clear()
      ..addAll(versions);
    notifyListeners();
  }
}
