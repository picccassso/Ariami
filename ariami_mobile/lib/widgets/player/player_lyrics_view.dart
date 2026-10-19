import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ariami_core/models/lyrics_models.dart';
import '../../models/song.dart';
import '../../services/lyrics/lyrics_service.dart';
import '../../services/playback_manager.dart';

/// Full-screen Apple Music-style lyrics viewing widget.
///
/// Supports synced lyrics with active line tracking, auto-scroll, seek on tap,
/// and plain lyrics with smooth scrolling.
class PlayerLyricsView extends StatefulWidget {
  final Song song;

  const PlayerLyricsView({
    super.key,
    required this.song,
  });

  @override
  State<PlayerLyricsView> createState() => _PlayerLyricsViewState();
}

class _PlayerLyricsViewState extends State<PlayerLyricsView> {
  final LyricsService _lyricsService = LyricsService();
  final PlaybackManager _playbackManager = PlaybackManager();
  final ScrollController _scrollController = ScrollController();

  SongLyrics? _lyrics;
  bool _isLoading = true;
  int _activeLineIndex = -1;
  bool _userIsScrolling = false;
  Timer? _userScrollResumeTimer;

  // GlobalKeys for each line item to ensure accurate auto-scrolling
  final List<GlobalKey> _lineKeys = [];

  @override
  void initState() {
    super.initState();
    _loadLyrics();
    _playbackManager.positionNotifier.addListener(_onPositionChanged);
  }

  @override
  void didUpdateWidget(covariant PlayerLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id) {
      _loadLyrics();
    }
  }

  @override
  void dispose() {
    _playbackManager.positionNotifier.removeListener(_onPositionChanged);
    _userScrollResumeTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadLyrics() async {
    setState(() {
      _isLoading = true;
      _activeLineIndex = -1;
      _lineKeys.clear();
    });

    final songId = widget.song.id;
    final lyrics = await _lyricsService.getLyrics(songId);
    // Drop stale results when the song changed while loading.
    if (!mounted || songId != widget.song.id) return;

    if (lyrics != null && lyrics.isSynced) {
      _lineKeys.addAll(
        List.generate(lyrics.lines.length, (_) => GlobalKey()),
      );
    }

    setState(() {
      _lyrics = lyrics;
      _isLoading = false;
    });

    _onPositionChanged();
  }

  void _onPositionChanged() {
    final lyrics = _lyrics;
    if (lyrics == null || !lyrics.isSynced || lyrics.lines.isEmpty) {
      return;
    }

    final newIndex =
        lyrics.activeLineIndexAt(_playbackManager.positionNotifier.value);

    if (newIndex != _activeLineIndex) {
      setState(() {
        _activeLineIndex = newIndex;
      });
      if (!_userIsScrolling && newIndex >= 0) {
        _scrollToActiveLine(newIndex);
      }
    }
  }

  void _scrollToActiveLine(int index) {
    if (index < 0 || index >= _lineKeys.length) return;
    final key = _lineKeys[index];
    final lineContext = key.currentContext;
    if (lineContext != null) {
      Scrollable.ensureVisible(
        lineContext,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
        alignment: 0.35, // Align ~1/3 down from the top (Apple Music style)
      );
    }
  }

  void _onUserScrolled() {
    _userIsScrolling = true;
    _userScrollResumeTimer?.cancel();
    _userScrollResumeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        _userIsScrolling = false;
        if (_activeLineIndex >= 0) {
          _scrollToActiveLine(_activeLineIndex);
        }
      }
    });
  }

  void _seekToLine(LyricsLine line) {
    _playbackManager.seek(line.timestamp);
    _userIsScrolling = false;
    _userScrollResumeTimer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    final lyrics = _lyrics;
    if (lyrics == null || lyrics.lines.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Text(
            'Lyrics not available',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (lyrics.isPlain) {
      return _buildPlainLyrics(lyrics, colorScheme);
    }

    return _buildSyncedLyrics(lyrics, colorScheme);
  }

  Widget _buildPlainLyrics(SongLyrics lyrics, ColorScheme colorScheme) {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 36.0),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lyrics.lines.map((line) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              line.text.isEmpty ? ' ' : line.text,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
                height: 1.4,
                color: colorScheme.onSurface.withValues(alpha: 0.9),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSyncedLyrics(SongLyrics lyrics, ColorScheme colorScheme) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is UserScrollNotification) {
          _onUserScrolled();
        }
        return false;
      },
      child: ShaderMask(
        shaderCallback: (Rect bounds) {
          return LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
            stops: const [0.0, 0.08, 0.90, 1.0],
          ).createShader(bounds);
        },
        blendMode: BlendMode.dstIn,
        // Every line is laid out (lyrics are short) so auto-scroll can reach
        // the active line even after a long seek.
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 80.0),
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: List.generate(lyrics.lines.length, (index) {
              final line = lyrics.lines[index];
              final isActive = index == _activeLineIndex;
              final isPast = index < _activeLineIndex;

              return GestureDetector(
                key: _lineKeys.length > index ? _lineKeys[index] : null,
                onTap: () => _seekToLine(line),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    style: TextStyle(
                      fontSize: isActive ? 26 : 22,
                      fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                      letterSpacing: -0.4,
                      height: 1.35,
                      color: isActive
                          ? colorScheme.onSurface
                          : (isPast
                              ? colorScheme.onSurface.withValues(alpha: 0.45)
                              : colorScheme.onSurface.withValues(alpha: 0.28)),
                      shadows: isActive
                          ? [
                              Shadow(
                                color: colorScheme.onSurface
                                    .withValues(alpha: 0.25),
                                blurRadius: 16,
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      line.text.isEmpty ? '♪' : line.text,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
