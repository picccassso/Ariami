import 'package:flutter/material.dart';
import '../../models/api_models.dart';
import '../album_detail_screen.dart';
import '../playlist/playlist_detail_screen.dart';
import 'search_screen.dart';

/// A navigator key for the search tab's nested navigation
final GlobalKey<NavigatorState> searchNavigatorKey = GlobalKey<NavigatorState>();

/// Wrapper widget that provides nested navigation for the Search tab.
/// This allows album/playlist detail screens to be shown within the tab
/// while keeping the bottom navigation bar and mini player visible.
class SearchNavigator extends StatelessWidget {
  const SearchNavigator({super.key, this.onBackAtRoot});

  /// Called when user presses back at the root of this navigator
  final VoidCallback? onBackAtRoot;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final navigator = searchNavigatorKey.currentState;
        if (navigator != null && navigator.canPop()) {
          navigator.pop();
        } else {
          onBackAtRoot?.call();
        }
      },
      child: Navigator(
      key: searchNavigatorKey,
      initialRoute: '/',
      onGenerateRoute: (settings) {
        Widget page;

        switch (settings.name) {
          case '/':
            page = const SearchScreen();
            break;
          case '/album':
            final album = settings.arguments as AlbumModel;
            page = AlbumDetailScreen(album: album);
            break;
          case '/playlist':
            final playlistId = settings.arguments as String;
            page = PlaylistDetailScreen(playlistId: playlistId);
            break;
          default:
            page = const SearchScreen();
        }

        return MaterialPageRoute(
          builder: (context) => page,
          settings: settings,
        );
      },
      ),
    );
  }
}
