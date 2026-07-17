import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'main/library_navigator.dart';
import 'main/search_navigator.dart';
import 'main/settings_navigator.dart';
import '../widgets/player/mini_player.dart';
import '../widgets/player/player_output_button.dart';
import '../widgets/player/sidebar_now_playing_card.dart';
import '../widgets/download/download_progress_bar.dart';
import '../widgets/common/bottom_chrome_metrics.dart';
import '../screens/full_player_screen.dart';
import '../services/cast/chrome_cast_service.dart';
import '../services/playback_manager.dart';
import '../services/ariami_connect_controller.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  final PlaybackManager _playbackManager = PlaybackManager();
  final ChromeCastService _castService = ChromeCastService();
  final AriamiConnectController _connect = AriamiConnectController();
  bool _refreshConnectOnResume = false;

  void _goToLibrary() {
    setState(() {
      _currentIndex = 0;
    });
  }

  void _exitApp() {
    SystemNavigator.pop();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Initialize playback manager and listen to changes
    _playbackManager.initialize();
    unawaited(_connect.start(_playbackManager));
    _playbackManager.addListener(_onPlaybackStateChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playbackManager.removeListener(_onPlaybackStateChanged);
    unawaited(_connect.stop());
    _playbackManager.dispose();
    super.dispose();
  }

  void _onPlaybackStateChanged() {
    // Rebuild UI when playback state changes
    setState(() {});
  }

  @override
  void didChangeMetrics() {
    // Rebuild when window metrics (notably the keyboard inset) change. The
    // outer Scaffold uses resizeToAvoidBottomInset: false, so it does not
    // rebuild on keyboard toggles on its own. Without this, the mini player
    // overlay would stay in the tree and hover above the keyboard.
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      unawaited(
        _castService.stopForAppTermination(reason: 'flutter-detached'),
      );
    }

    // Persist playback state when app goes to background/closed
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(_playbackManager.saveStateImmediately());
    }

    // A mobile OS may suspend the Connect socket without closing it. Only a
    // real background transition should trigger the authoritative refresh;
    // transient inactive states (dialogs, notification shade) should not.
    if (state == AppLifecycleState.paused) {
      _refreshConnectOnResume = true;
    } else if (state == AppLifecycleState.resumed && _refreshConnectOnResume) {
      _refreshConnectOnResume = false;
      unawaited(_connect.refresh());
    }
  }

  void _onTabTapped(int index) {
    if (index == _currentIndex) {
      // Tapping the current tab - pop nested navigator to root
      switch (index) {
        case 0:
          libraryNavigatorKey.currentState?.popUntil((route) => route.isFirst);
          break;
        case 1:
          searchNavigatorKey.currentState?.popUntil((route) => route.isFirst);
          break;
        case 2:
          settingsNavigatorKey.currentState?.popUntil((route) => route.isFirst);
          break;
      }
    } else {
      // Switching to a different tab
      setState(() {
        _currentIndex = index;
      });
    }
  }

  void _openFullPlayer() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const FullPlayerScreen(),
      ),
    );
  }

  Widget _buildCurrentScreen() {
    switch (_currentIndex) {
      case 0:
        return LibraryNavigator(onBackAtRoot: _exitApp);
      case 1:
        return SearchNavigator(onBackAtRoot: _goToLibrary);
      case 2:
        return SettingsNavigator(onBackAtRoot: _goToLibrary);
      default:
        return LibraryNavigator(onBackAtRoot: _exitApp);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomNavHeight = getBottomNavigationBarTotalHeight(context);
    final keyboardOpen = isKeyboardOpen(context);
    // Wide (tablet/landscape) layouts navigate with an extended sidebar
    // instead of a bottom bar; the mini player docks at the bottom of that
    // sidebar (Spotify-style), so the content overlay is phone-only.
    final useRail = useNavigationRail(context);
    final content = Stack(
      children: [
        // Main content area - can scroll behind nav bar
        _buildCurrentScreen(),
        // Mini player and download bar - positioned above nav bar.
        // Hidden while the keyboard is open so it doesn't hover above it.
        if (!keyboardOpen && !useRail)
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomNavHeight,
            child: _buildMiniPlayerChrome(),
          ),
      ],
    );
    return Scaffold(
      extendBody: true,
      // Don't shrink the body when the keyboard opens. The nested screens
      // (e.g. search) handle their own keyboard avoidance, while the mini
      // player overlay is hidden entirely so it never hovers above the
      // keyboard.
      resizeToAvoidBottomInset: false,
      body: useRail
          ? Row(
              children: [
                _buildNavigationSidebar(context),
                VerticalDivider(
                  width: 0.5,
                  thickness: 0.5,
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                ),
                Expanded(child: content),
              ],
            )
          : content,
      bottomNavigationBar: useRail
          ? null
          : ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .scaffoldBackgroundColor
                        .withValues(alpha: 0.85),
                    border: Border(
                      top: BorderSide(
                        color: Theme.of(context)
                            .dividerColor
                            .withValues(alpha: 0.5),
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: BottomNavigationBar(
                      currentIndex: _currentIndex,
                      onTap: _onTabTapped,
                      items: const [
                        BottomNavigationBarItem(
                          icon: Icon(Icons.library_music),
                          label: 'Library',
                        ),
                        BottomNavigationBarItem(
                          icon: Icon(Icons.search),
                          label: 'Search',
                        ),
                        BottomNavigationBarItem(
                          icon: Icon(Icons.settings),
                          label: 'Settings',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  /// Mini player + download progress bar. Overlaid above the bottom nav on
  /// phones; docked at the bottom of the navigation sidebar on wide layouts.
  Widget _buildMiniPlayerChrome() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MiniPlayer(
          currentSong: _playbackManager.currentSong,
          isPlaying: _playbackManager.isPlaying,
          isVisible: _playbackManager.currentSong != null,
          onTap: _openFullPlayer,
          onPlayPause: _playbackManager.togglePlayPause,
          onSkipNext: _playbackManager.skipNext,
          onSkipPrevious: _playbackManager.skipPrevious,
          hasNext: _playbackManager.hasNext,
          hasPrevious: _playbackManager.hasPrevious,
          position: _playbackManager.position,
          duration: _playbackManager.duration ?? Duration.zero,
          playbackManager: _playbackManager,
        ),
        const DownloadProgressBar(),
      ],
    );
  }

  /// Vertical now-playing card for the sidebar. The horizontal MiniPlayer
  /// bar is phone-only — squeezed into 240px it clips its text and icons.
  Widget _buildSidebarNowPlaying() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SidebarNowPlayingCard(
          currentSong: _playbackManager.currentSong,
          isPlaying: _playbackManager.isPlaying,
          onTap: _openFullPlayer,
          onPlayPause: _playbackManager.togglePlayPause,
          onSkipNext: _playbackManager.skipNext,
          onSkipPrevious: _playbackManager.skipPrevious,
          hasNext: _playbackManager.hasNext,
          hasPrevious: _playbackManager.hasPrevious,
          position: _playbackManager.position,
          duration: _playbackManager.duration ?? Duration.zero,
        ),
        const DownloadProgressBar(),
      ],
    );
  }

  /// Extended navigation sidebar for wide layouts: destinations on top, the
  /// now-playing card docked at the bottom (Spotify-style).
  Widget _buildNavigationSidebar(BuildContext context) {
    return SafeArea(
      right: false,
      child: SizedBox(
        width: 240,
        child: Column(
          children: [
            Expanded(
              child: NavigationRail(
                selectedIndex: _currentIndex,
                onDestinationSelected: _onTabTapped,
                extended: true,
                minExtendedWidth: 240,
                backgroundColor: Colors.transparent,
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.library_music),
                    label: Text('Library'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.search),
                    label: Text('Search'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.settings),
                    label: Text('Settings'),
                  ),
                ],
              ),
            ),
            // Standing Ariami Connect entry — reachable without opening the
            // full player, and visible even when nothing is playing.
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: PlayerOutputButton(
                  playbackManager: _playbackManager,
                  fallbackLabel: 'Ariami Connect',
                ),
              ),
            ),
            _buildSidebarNowPlaying(),
          ],
        ),
      ),
    );
  }
}
