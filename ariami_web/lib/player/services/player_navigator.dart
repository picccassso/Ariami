import 'package:flutter/foundation.dart';

import '../models/player_models.dart';

enum PlayerViewKind {
  home,
  albums,
  songs,
  album,
  playlist,
  artist,
  search,
  discovery,
  recentlyPlayed,
  settings,
}

@immutable
class PlayerView {
  final PlayerViewKind kind;

  /// Album or playlist id, or artist name, when relevant.
  final String? id;

  const PlayerView(this.kind, {this.id});

  static const home = PlayerView(PlayerViewKind.home);
  static const albums = PlayerView(PlayerViewKind.albums);
  static const songs = PlayerView(PlayerViewKind.songs);
  static const search = PlayerView(PlayerViewKind.search);
  static const discovery = PlayerView(PlayerViewKind.discovery);
  static const recentlyPlayed = PlayerView(PlayerViewKind.recentlyPlayed);
  static const settings = PlayerView(PlayerViewKind.settings);

  @override
  bool operator ==(Object other) =>
      other is PlayerView && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

class PlayerNavigator extends ChangeNotifier {
  final List<PlayerView> _back = <PlayerView>[PlayerView.home];
  final List<PlayerView> _forward = <PlayerView>[];

  PlayerView get current => _back.last;
  bool get canGoBack => _back.length > 1;
  bool get canGoForward => _forward.isNotEmpty;

  bool _rightPanelOpen = true;
  bool get rightPanelOpen => _rightPanelOpen;

  bool _sidebarCollapsed = false;
  bool get sidebarCollapsed => _sidebarCollapsed;

  void go(PlayerView view) {
    if (view == current) {
      notifyListeners();
      return;
    }
    _back.add(view);
    _forward.clear();
    notifyListeners();
  }

  void goBack() {
    if (!canGoBack) return;
    _forward.add(_back.removeLast());
    notifyListeners();
  }

  void goForward() {
    if (!canGoForward) return;
    _back.add(_forward.removeLast());
    notifyListeners();
  }

  void openAllAlbums() => go(PlayerView.albums);
  void openAllSongs() => go(PlayerView.songs);
  void openAlbum(String id) => go(PlayerView(PlayerViewKind.album, id: id));
  void openPlaylist(String id) =>
      go(PlayerView(PlayerViewKind.playlist, id: id));
  void openArtist(String name) =>
      go(PlayerView(PlayerViewKind.artist, id: name));

  void toggleRightPanel() {
    _rightPanelOpen = !_rightPanelOpen;
    notifyListeners();
  }

  void toggleSidebar() {
    _sidebarCollapsed = !_sidebarCollapsed;
    notifyListeners();
  }
}

/// Plain holder so the search query can be shared via `Provider` without
/// tripping Provider's Listenable check (it wraps, but is not itself one).
class SearchQueryHolder {
  final ValueNotifier<String> query = ValueNotifier<String>('');

  /// Keyboard-highlighted song in the search results, navigated with ↑/↓ from
  /// the search field. -1 means nothing is highlighted yet. Reset whenever the
  /// query changes so the selection never points past the new result list.
  final ValueNotifier<int> selectedIndex = ValueNotifier<int>(-1);

  /// Bumped when focus should be returned to the search input field.
  final ValueNotifier<int> refocusTick = ValueNotifier<int>(0);

  /// Song results of the latest search, published by the search view so the
  /// top bar's ↑/↓ and Enter reuse them instead of searching again.
  Future<List<Track>> songs = Future<List<Track>>.value(const <Track>[]);

  void clear() {
    query.value = '';
    selectedIndex.value = -1;
    songs = Future<List<Track>>.value(const <Track>[]);
  }

  void requestFocus() {
    refocusTick.value++;
  }

  void dispose() {
    query.dispose();
    selectedIndex.dispose();
    refocusTick.dispose();
  }
}
