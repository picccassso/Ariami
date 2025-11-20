import 'package:flutter/material.dart';
import 'main/library_screen.dart';
import 'main/search_screen.dart';
import 'main/settings_screen.dart';
import '../widgets/player/mini_player.dart';
import '../screens/full_player_screen.dart';
import '../services/playback_manager.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  final PlaybackManager _playbackManager = PlaybackManager();

  // List of screens for each tab
  final List<Widget> _screens = const [
    LibraryScreen(),
    SearchScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Initialize playback manager and listen to changes
    _playbackManager.initialize();
    _playbackManager.addListener(_onPlaybackStateChanged);
  }

  @override
  void dispose() {
    _playbackManager.removeListener(_onPlaybackStateChanged);
    super.dispose();
  }

  void _onPlaybackStateChanged() {
    // Rebuild UI when playback state changes
    setState(() {});
  }

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  void _openFullPlayer() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const FullPlayerScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Main content area
          Expanded(
            child: _screens[_currentIndex],
          ),

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
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
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
    );
  }
}
