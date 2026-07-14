import '../../models/api_models.dart';
import '../api/connection_service.dart';

/// Resolves catalog album metadata for lightweight song records.
///
/// The synced song model intentionally stores the album ID rather than a
/// duplicated album title. Playback and download records still need the
/// display metadata, though, so they must resolve it before persisting stats
/// or queue entries. Results are cached for the current connection scope.
class AlbumMetadataResolver {
  AlbumMetadataResolver._internal();

  static final AlbumMetadataResolver _instance =
      AlbumMetadataResolver._internal();

  factory AlbumMetadataResolver() => _instance;

  final ConnectionService _connection = ConnectionService();
  final Map<String, AlbumModel> _cache = <String, AlbumModel>{};
  String? _cacheScope;

  Future<AlbumModel?> resolve(String? albumId) async {
    final normalizedId = albumId?.trim();
    if (normalizedId == null || normalizedId.isEmpty) return null;

    final scope = '${_connection.apiClient?.baseUrl ?? ''}|'
        '${_connection.userId ?? ''}';
    if (_cacheScope != scope) {
      _cacheScope = scope;
      _cache.clear();
    }

    final cached = _cache[normalizedId];
    if (cached != null) return cached;

    try {
      final album =
          await _connection.libraryReadFacade.getAlbumById(normalizedId);
      // A missing row during bootstrap is transient. Only cache successful
      // resolutions so later playback/download attempts can self-heal once
      // the normalized catalog finishes syncing.
      if (album != null) _cache[normalizedId] = album;
      return album;
    } catch (_) {
      // Metadata repair is best-effort. Playback/download must continue even
      // when the local catalog is temporarily unavailable.
      return null;
    }
  }
}
