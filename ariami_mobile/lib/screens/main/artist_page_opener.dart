/// Hands "open this artist's page" requests from anywhere in the app to the
/// main navigation.
///
/// Detail routes like `/artist` live in the active tab's nested navigator.
/// Screens outside the tab (like the full-screen player, which sits on the root
/// navigator) therefore open artist pages through this handoff: the main
/// navigation registers a callback while it is alive and forwards the artist
/// name through it into whichever tab is currently mounted.
class ArtistPageOpener {
  ArtistPageOpener._();

  static final ArtistPageOpener _instance = ArtistPageOpener._();
  factory ArtistPageOpener() => _instance;

  void Function(String artistName)? _open;

  /// Registered by MainNavigationScreen while it is mounted.
  void register(void Function(String artistName) open) => _open = open;

  /// Drops the callback when the registering screen unmounts.
  void unregister(void Function(String artistName) open) {
    if (_open == open) _open = null;
  }

  /// Opens the artist page, or does nothing when the main navigation is not
  /// up yet.
  void open(String artistName) => _open?.call(artistName);
}
