import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'main/library_navigator.dart';
import 'main/search_navigator.dart';
import 'main/settings_navigator.dart';
import '../widgets/player/mini_player.dart';
import '../widgets/download/download_progress_bar.dart';
import '../screens/full_player_screen.dart';
import '../services/playback_manager.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  final PlaybackManager _playbackManager = PlaybackManager();

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
    _playbackManager.addListener(_onPlaybackStateChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playbackManager.removeListener(_onPlaybackStateChanged);
    _playbackManager.dispose();
    super.dispose();
  }

  void _onPlaybackStateChanged() {
    // Rebuild UI when playback state changes
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Persist playback state when app goes to background/closed
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.detached) {
      _playbackManager.saveStateImmediately();
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
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          // Main content area - can scroll behind nav bar
          _buildCurrentScreen(),
          // Mini player and download bar - positioned above nav bar
          Positioned(
            left: 0,
            right: 0,
            bottom: kBottomNavigationBarHeight,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Mini player connected to real playback
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
                ),
                // Download progress bar (between mini player and bottom nav)
                const DownloadProgressBar(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
            ),
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
    );
  }
}
