import '../../models/api_models.dart';

/// Hands "open this album's page" requests from anywhere in the app to the
/// main navigation.
///
/// Detail routes like `/album` live in the active tab's nested navigator.
/// Screens outside the tab (like the full-screen player, which sits on the root
/// navigator) therefore open album pages through this handoff: the main
/// navigation registers a callback while it is alive and forwards the album
/// through it into whichever tab is currently mounted.
class AlbumPageOpener {
  AlbumPageOpener._();

  static final AlbumPageOpener _instance = AlbumPageOpener._();
  factory AlbumPageOpener() => _instance;

  void Function(AlbumModel album)? _open;

  /// Registered by MainNavigationScreen while it is mounted.
  void register(void Function(AlbumModel album) open) => _open = open;

  /// Drops the callback when the registering screen unmounts.
  void unregister(void Function(AlbumModel album) open) {
    if (_open == open) _open = null;
  }

  /// Opens the album page, or does nothing when the main navigation is not
  /// up yet.
  void open(AlbumModel album) => _open?.call(album);
}
