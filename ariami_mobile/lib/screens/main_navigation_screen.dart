import '../widgets/music_availability_banner.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/api_models.dart';
import 'main/album_page_opener.dart';
import 'main/artist_page_opener.dart';
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
import '../services/theme_service.dart';
import '../widgets/common/ambient_backdrop.dart';
import '../services/ariami_connect_controller.dart';
import '../utils/constants.dart';
import '../widgets/common/queue_action_confirmation.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  final List<bool> _visitedTabs = <bool>[true, false, false];
  final PlaybackManager _playbackManager = PlaybackManager();
  final ChromeCastService _castService = ChromeCastService();
  final AriamiConnectController _connect = AriamiConnectController();
  final ValueNotifier<int> _searchTabReselections = ValueNotifier<int>(0);
  bool _refreshConnectOnResume = false;
  StreamSubscription<Future<void> Function()>? _queueReplacedSubscription;

  void _selectTab(int index) {
    if (_currentIndex == index) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _currentIndex = index;
      _visitedTabs[index] = true;
    });
  }

  void _goToLibrary() => _selectTab(0);

  GlobalKey<NavigatorState> get _currentNavigatorKey {
    switch (_currentIndex) {
      case 0:
        return libraryNavigatorKey;
      case 1:
        return searchNavigatorKey;
      case 2:
        return settingsNavigatorKey;
      default:
        return libraryNavigatorKey;
    }
  }

  /// Opens an artist's page in the currently active tab's nested navigator so
  /// returning keeps the user's tab context intact.
  void _openArtistPage(String artistName) {
    final nav = _currentNavigatorKey.currentState;
    if (nav != null) {
      nav.pushNamed('/artist', arguments: artistName);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _currentNavigatorKey.currentState
            ?.pushNamed('/artist', arguments: artistName);
      });
    }
  }

  /// Opens an album's page in the currently active tab's nested navigator so
  /// returning keeps the user's tab context intact.
  void _openAlbumPage(AlbumModel album) {
    final nav = _currentNavigatorKey.currentState;
    if (nav != null) {
      nav.pushNamed('/album', arguments: album);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _currentNavigatorKey.currentState
            ?.pushNamed('/album', arguments: album);
      });
    }
  }

  Future<void> _exitApp() async {
    await _connect.leave();
    await SystemNavigator.pop();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ArtistPageOpener().register(_openArtistPage);
    AlbumPageOpener().register(_openAlbumPage);
    _playbackManager.initialize();
    unawaited(_connect.start(_playbackManager));
    _playbackManager.addListener(_onPlaybackStateChanged);
    _queueReplacedSubscription =
        _playbackManager.queueReplacedStream.listen((undo) {
      if (!mounted) return;
      showUndoToast(
        context,
        'Queue replaced',
        onUndo: () => unawaited(undo()),
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playbackManager.removeListener(_onPlaybackStateChanged);
    _queueReplacedSubscription?.cancel();
    ArtistPageOpener().unregister(_openArtistPage);
    AlbumPageOpener().unregister(_openAlbumPage);
    _searchTabReselections.dispose();
    // Widget/view teardown is not proof that the Android process or its
    // background audio service is exiting. Keep local playback untouched.
    unawaited(_connect.stop());
    _playbackManager.dispose();
    super.dispose();
  }

  void _onPlaybackStateChanged() {
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      unawaited(
        _castService.stopForAppTermination(reason: 'flutter-detached'),
      );
      // Flutter reports detached when all views are detached, including
      // Android activity recreation. The Connect socket itself is the
      // authoritative process-death signal, so do not pause playback here.
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
      switch (index) {
        case 0:
          libraryNavigatorKey.currentState?.popUntil((route) => route.isFirst);
          break;
        case 1:
          final navigator = searchNavigatorKey.currentState;
          if (navigator?.canPop() ?? false) {
            navigator?.popUntil((route) => route.isFirst);
          } else {
            _searchTabReselections.value++;
          }
          break;
        case 2:
          settingsNavigatorKey.currentState?.popUntil((route) => route.isFirst);
          break;
      }
    } else {
      _selectTab(index);
    }
  }

  void _openFullPlayer() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const FullPlayerScreen(),
      ),
    );
  }

  Widget _tabSlot(int index, Widget child) {
    final isActive = _currentIndex == index;
    return TickerMode(
      enabled: isActive,
      child: ExcludeFocus(
        excluding: !isActive,
        child: child,
      ),
    );
  }

  Widget _buildCurrentScreen() {
    return IndexedStack(
      index: _currentIndex,
      children: [
        _tabSlot(
          0,
          LibraryNavigator(
            onBackAtRoot: _exitApp,
            isActive: _currentIndex == 0,
          ),
        ),
        if (_visitedTabs[1])
          _tabSlot(
            1,
            SearchNavigator(
              onBackAtRoot: _goToLibrary,
              reselectionRequests: _searchTabReselections,
              isActive: _currentIndex == 1,
            ),
          )
        else
          const SizedBox.shrink(),
        if (_visitedTabs[2])
          _tabSlot(
            2,
            SettingsNavigator(
              onBackAtRoot: _goToLibrary,
              isActive: _currentIndex == 2,
            ),
          )
        else
          const SizedBox.shrink(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Wide (tablet/landscape) layouts navigate with an extended sidebar
    // instead of a bottom bar; the mini player docks at the bottom of that
    // sidebar (Spotify-style), so the content overlay is phone-only.
    final useRail = useNavigationRail(context);
    final colors = context.colors;
    final content = Stack(
      children: [
        Column(
          children: [
            const MusicAvailabilityBanner(),
            Expanded(child: _buildCurrentScreen()),
          ],
        ),
        // Mini player and download bar - positioned above nav bar.
        // Hidden while the keyboard is open so it doesn't hover above it.
        if (!useRail)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _KeyboardAwareMiniPlayerOverlay(
              child: _buildMiniPlayerChrome(),
            ),
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
      body: Stack(
        fit: StackFit.expand,
        children: [
          // The sleeve's two-ink ground, or the glow while the moving
          // background is on.
          Positioned.fill(
            child: ListenableBuilder(
              listenable: Listenable.merge([ThemeService(), _playbackManager]),
              builder: (context, _) {
                if (!ThemeService().movingBackdrop) {
                  return DecoratedBox(
                    decoration: BoxDecoration(gradient: colors.groundGradient),
                  );
                }
                final song = _playbackManager.currentSong;
                return PlayerBackdrop(
                  layoutSeed: (song?.albumId ?? song?.id ?? '').hashCode,
                );
              },
            ),
          ),
          useRail
              ? Row(
                  children: [
                    _buildNavigationSidebar(context),
                    VerticalDivider(
                      width: 0.5,
                      thickness: 0.5,
                      color: colors.border,
                    ),
                    Expanded(child: content),
                  ],
                )
              : content,
        ],
      ),
      bottomNavigationBar: useRail
          ? null
          // The same band as the mini player above it, so the bottom chrome
          // reads as one transport bar.
          : DecoratedBox(
              decoration: BoxDecoration(
                color: colors.band,
                border: Border(top: BorderSide(color: colors.border)),
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

class _KeyboardAwareMiniPlayerOverlay extends StatefulWidget {
  const _KeyboardAwareMiniPlayerOverlay({required this.child});

  final Widget child;

  @override
  State<_KeyboardAwareMiniPlayerOverlay> createState() =>
      _KeyboardAwareMiniPlayerOverlayState();
}

class _KeyboardAwareMiniPlayerOverlayState
    extends State<_KeyboardAwareMiniPlayerOverlay> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (isKeyboardOpen(context)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.only(bottom: getBottomNavigationBarTotalHeight(context)),
      child: widget.child,
    );
  }
}
