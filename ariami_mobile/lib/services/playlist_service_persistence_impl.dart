part of 'playlist_service.dart';

extension _PlaylistServicePersistenceImpl on PlaylistService {
  Future<void> _loadPlaylistsImpl() async {
    if (_isLoaded) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      final jsonString = prefs.getString(PlaylistService._storageKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> jsonList = json.decode(jsonString);
        _playlists = jsonList
            .map((entry) =>
                PlaylistModel.fromJson(entry as Map<String, dynamic>))
            .toList();
      }

      final hiddenJson =
          prefs.getString(PlaylistService._hiddenServerPlaylistsKey);
      if (hiddenJson != null && hiddenJson.isNotEmpty) {
        final List<dynamic> hiddenList = json.decode(hiddenJson);
        _hiddenServerPlaylistIds = hiddenList.cast<String>().toSet();
      }

      final importedJson =
          prefs.getString(PlaylistService._importedFromServerKey);
      if (importedJson != null && importedJson.isNotEmpty) {
        final Map<String, dynamic> importedMap = json.decode(importedJson);
        _importedFromServer =
            importedMap.map((key, value) => MapEntry(key, value as String));
      }

      final pendingJson =
          prefs.getString(PlaylistService._pendingImportedEditPushesKey);
      if (pendingJson != null && pendingJson.isNotEmpty) {
        final List<dynamic> pendingList = json.decode(pendingJson);
        _pendingImportedEditPushes = pendingList.cast<String>().toSet();
      }

      _isLoaded = true;
      _notifyListeners();
    } catch (error) {
      print('[PlaylistService] Error loading playlists: $error');
      _playlists = [];
      _isLoaded = true;
      _notifyListeners();
    }
  }

  Future<void> _savePlaylists() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _playlists.map((playlist) => playlist.toJson()).toList();
      await prefs.setString(PlaylistService._storageKey, json.encode(jsonList));
    } catch (error) {
      print('[PlaylistService] Error saving playlists: $error');
    }
  }

  Future<void> _saveHiddenServerPlaylists() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        PlaylistService._hiddenServerPlaylistsKey,
        json.encode(_hiddenServerPlaylistIds.toList()),
      );
    } catch (error) {
      print('[PlaylistService] Error saving hidden server playlists: $error');
    }
  }

  Future<void> _savePendingImportedEditPushes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        PlaylistService._pendingImportedEditPushesKey,
        json.encode(_pendingImportedEditPushes.toList()),
      );
    } catch (error) {
      print(
        '[PlaylistService] Error saving pending imported edit pushes: $error',
      );
    }
  }

  Future<void> _saveImportedFromServer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        PlaylistService._importedFromServerKey,
        json.encode(_importedFromServer),
      );
    } catch (error) {
      print(
        '[PlaylistService] Error saving imported from server mapping: $error',
      );
    }
  }
}
