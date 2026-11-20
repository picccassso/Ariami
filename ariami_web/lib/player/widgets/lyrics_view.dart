import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ariami_core/models/lyrics_models.dart';

import '../services/audio_controller.dart';
import '../services/lyrics_controller.dart';
import '../theme/player_theme.dart';

/// Desktop lyrics view for both compact (NowPlayingPanel) and expanded (FullNowPlayingView) displays.
class LyricsView extends StatefulWidget {
  final bool compact;

  /// Drop the side inset, so lines start flush with whatever sits above.
  final bool flush;

  const LyricsView({
    super.key,
    this.compact = false,
    this.flush = false,
  });

  double get _inset => flush ? 0 : (compact ? 16 : 36);

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  final ScrollController _scrollController = ScrollController();
  AudioController? _audio;
  int _activeLineIndex = -1;
  int? _hoveredIndex;
  bool _userIsScrolling = false;
  Timer? _userScrollResumeTimer;
  final List<GlobalKey> _lineKeys = <GlobalKey>[];
  String? _lastLyricsSongId;

  /// The first scroll to the active line jumps rather than animates, so
  /// opening lyrics mid-song lands on the line instead of racing down to it.
  bool _snapNextScroll = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newAudio = context.read<AudioController>();
    if (!identical(_audio, newAudio)) {
      _audio?.removeTickingListener(_onPositionChanged);
      _audio = newAudio;
      _audio?.addTickingListener(_onPositionChanged);
    }
  }

  @override
  void dispose() {
    _audio?.removeTickingListener(_onPositionChanged);
    _userScrollResumeTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _syncLineKeys(SongLyrics lyrics) {
    if (_lastLyricsSongId != lyrics.songId || _lineKeys.length != lyrics.lines.length) {
      _lastLyricsSongId = lyrics.songId;
      _lineKeys.clear();
      _lineKeys.addAll(List.generate(lyrics.lines.length, (_) => GlobalKey()));
      _activeLineIndex = -1;
      _snapNextScroll = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _onPositionChanged());
    }
  }

  void _onPositionChanged() {
    if (!mounted) return;
    final lyricsController = context.read<LyricsController?>();
    final lyrics = lyricsController?.currentLyrics;
    final audio = _audio;
    if (lyrics == null || !lyrics.isSynced || lyrics.lines.isEmpty || audio == null) {
      return;
    }

    final newIndex = lyrics.activeLineIndexAt(audio.position);
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
        duration: _snapNextScroll
            ? Duration.zero
            : const Duration(milliseconds: 380),
        curve: Curves.easeInOutCubic,
        alignment: widget.compact ? 0.30 : 0.35,
      );
      _snapNextScroll = false;
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
    _audio?.seek(line.timestamp);
    _userIsScrolling = false;
    _userScrollResumeTimer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final lyricsController = context.watch<LyricsController?>();
    final lyrics = lyricsController?.currentLyrics;
    final isLoading = lyricsController?.isLoading ?? false;

    if (isLoading) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }

    if (lyrics == null || lyrics.lines.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            'Lyrics not available',
            style: TextStyle(
              fontSize: widget.compact ? 14 : 18,
              fontWeight: FontWeight.w600,
              color: context.colors.textSecondary.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    _syncLineKeys(lyrics);

    if (lyrics.isPlain) {
      return _buildPlainLyrics(lyrics);
    }

    return _buildSyncedLyrics(lyrics);
  }

  Widget _buildPlainLyrics(SongLyrics lyrics) {
    return ShaderMask(
      shaderCallback: (bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: [0.0, 0.06, 0.94, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: EdgeInsets.symmetric(
          horizontal: widget._inset,
          vertical: widget.compact ? 24 : 48,
        ),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: lyrics.lines.map((line) {
            return Padding(
              padding: EdgeInsets.symmetric(
                vertical: widget.compact ? 4 : 8,
              ),
              child: SelectableText(
                line.text.isEmpty ? ' ' : line.text,
                style: TextStyle(
                  fontSize: widget.compact ? 15 : 22,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                  height: 1.45,
                  color: context.colors.textPrimary.withValues(alpha: 0.9),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSyncedLyrics(SongLyrics lyrics) {
    final activeColor = Theme.of(context).colorScheme.secondary;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is UserScrollNotification) {
          _onUserScrolled();
        }
        return false;
      },
      child: ShaderMask(
        shaderCallback: (bounds) {
          return const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
            stops: [0.0, 0.08, 0.92, 1.0],
          ).createShader(bounds);
        },
        blendMode: BlendMode.dstIn,
        // Every line is laid out (lyrics are short) so auto-scroll can reach
        // the active line even after a long seek.
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: EdgeInsets.symmetric(
            horizontal: widget._inset,
            vertical: widget.compact ? 48 : 80,
          ),
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: List.generate(lyrics.lines.length, (index) {
              final line = lyrics.lines[index];
              final isActive = index == _activeLineIndex;
              final isPast = index < _activeLineIndex;
              final isHovered = index == _hoveredIndex;

              final double fontSize = widget.compact
                  ? (isActive ? 18.0 : 15.0)
                  : (isActive ? 28.0 : 22.0);

              Color textColor;
              if (isActive) {
                textColor = context.colors.textPrimary;
              } else if (isHovered) {
                textColor = context.colors.textPrimary.withValues(alpha: 0.85);
              } else if (isPast) {
                textColor =
                    context.colors.textSecondary.withValues(alpha: 0.55);
              } else {
                textColor =
                    context.colors.textSecondary.withValues(alpha: 0.35);
              }

              return MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _hoveredIndex = index),
                onExit: (_) => setState(() {
                  if (_hoveredIndex == index) _hoveredIndex = null;
                }),
                child: GestureDetector(
                  key: _lineKeys.length > index ? _lineKeys[index] : null,
                  onTap: () => _seekToLine(line),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: widget.compact ? 8 : 14,
                    ),
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight:
                            isActive ? FontWeight.w800 : FontWeight.w600,
                        letterSpacing: isActive ? -0.5 : -0.2,
                        height: 1.35,
                        color: textColor,
                        shadows: isActive
                            ? [
                                Shadow(
                                  color: activeColor.withValues(alpha: 0.4),
                                  blurRadius: 20,
                                ),
                              ]
                            : null,
                      ),
                      child: Text(
                        line.text.isEmpty ? '♪' : line.text,
                      ),
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
