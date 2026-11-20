import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ariami_core/utils/format.dart';

import '../services/audio/audio_level_meter.dart';
import '../models/player_models.dart';
import '../services/ariami_connect_controller.dart';
import '../services/audio_controller.dart';
import '../services/connection_controller.dart';
import '../services/library_controller.dart';
import '../services/lyrics_controller.dart';
import '../services/player_host.dart';
import '../services/player_navigator.dart';
import '../services/theme_controller.dart';
import '../theme/motion.dart';
import '../theme/player_theme.dart';
import 'ariami_connect_sheet.dart';
import 'album_link.dart';
import 'ambient_backdrop.dart';
import 'artwork.dart';
import 'artist_credit_links.dart';
import 'blurred_cover.dart';
import 'context_menu.dart';
import 'hover_slider.dart';
import 'liked_song_button.dart';
import 'lyrics_view.dart';
import 'player_bar.dart' show ProgressBand, TransportToggle;
import 'playlists_menu.dart';
import 'playback_helpers.dart';
import 'queue_list.dart';
import 'seek_slider.dart';
import 'spotlight_modal.dart';
import 'track_title_link.dart';

Future<void> showFullNowPlaying(BuildContext context) {
  final audio = context.read<AudioController>();
  final connection = context.read<ConnectionController>();
  final connect = context.read<AriamiConnectController>();
  final library = context.read<LibraryController>();
  final navigator = context.read<PlayerNavigator>();
  final theme = context.read<ThemeController>();
  final host = maybeReadHost(context);
  final downloads = maybeReadProvider<PlayerDownloadsBridge?>(context) ??
      maybeReadProvider<PlayerDownloadsBridge>(context);
  final lyrics = maybeReadProvider<LyricsController?>(context) ??
      maybeReadProvider<LyricsController>(context);

  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: true,
      fullscreenDialog: false,
      transitionDuration: Motion.medium,
      reverseTransitionDuration: Motion.medium,
      pageBuilder: (context, animation, secondaryAnimation) => MultiProvider(
        providers: [
          if (host != null) ...[
            Provider<PlayerHost>.value(value: host),
            Provider<PlayerHost?>.value(value: host),
          ],
          ChangeNotifierProvider<AudioController>.value(value: audio),
          ChangeNotifierProvider<ConnectionController>.value(value: connection),
          ChangeNotifierProvider<AriamiConnectController>.value(value: connect),
          ChangeNotifierProvider<LibraryController>.value(value: library),
          ChangeNotifierProvider<PlayerNavigator>.value(value: navigator),
          ChangeNotifierProvider<ThemeController>.value(value: theme),
          ChangeNotifierProvider<PlayerDownloadsBridge?>.value(value: downloads),
          if (lyrics != null)
            ChangeNotifierProvider<LyricsController>.value(value: lyrics),
        ],
        // The root-navigator route sits above the shell's nested AnimatedTheme,
        // so it can't inherit the player theme. Rebuild it here from the live
        // controller — a pinned Theme.of snapshot froze the fullscreen player
        // on whatever colour was active when it opened, so the dynamic
        // cover-art theme never followed song changes.
        child: Consumer<ThemeController>(
          builder: (context, theme, child) {
            final data = theme.themeMode == ThemeMode.light
                ? theme.lightTheme
                : theme.darkTheme;
            return AnimatedTheme(
              data: data,
              duration: const Duration(milliseconds: 400),
              child: child!,
            );
          },
          child: const FullNowPlayingView(),
        ),
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved =
            CurvedAnimation(parent: animation, curve: Motion.standard);
        final offset = Tween<Offset>(
          begin: const Offset(0, 0.03),
          end: Offset.zero,
        ).animate(curved);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(position: offset, child: child),
        );
      },
    ),
  );
}

class FullNowPlayingView extends StatefulWidget {
  const FullNowPlayingView({super.key});

  static const queuePinnedPrefKey = 'full_now_playing_queue_pinned';

  @override
  State<FullNowPlayingView> createState() => _FullNowPlayingViewState();
}

class _FullNowPlayingViewState extends State<FullNowPlayingView>
    with WidgetsBindingObserver {
  bool _queueOpen = false;
  bool _queuePinned = false;

  /// Set once the user opens, closes, or pins the queue so an in-flight
  /// preference read can never overwrite their interaction.
  bool _queueTouched = false;

  /// Matches the TV fullscreen player: after this much inactivity while
  /// playing, everything but the artwork, title and artist hides.
  static const _idleDelay = Duration(seconds: 90);

  static final _wakeKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.space,
  };

  final _rootFocus = FocusNode(debugLabel: 'Full now playing root');
  final _idleFocus = FocusNode(debugLabel: 'Full now playing idle');
  final _wakePresses = <PhysicalKeyboardKey>{};
  AudioController? _audio;
  ModalRoute<dynamic>? _route;
  Timer? _idleTimer;
  FocusNode? _previousFocus;
  bool _controlsVisible = true;
  bool _idleEnabled = false;
  late bool _appActive;

  /// Deliberately excludes `isLoading`: an automatic song change flips
  /// loading while playback continues, and hidden chrome must stay hidden
  /// across the change — only a real pause/stop (or no track, a hidden
  /// window, or leaving this route) reveals it.
  bool get _canIdle =>
      _appActive &&
      (_route?.isCurrent ?? false) &&
      (_audio?.currentTrack != null) &&
      (_audio?.isPlaying ?? false);

  @override
  void initState() {
    super.initState();
    _appActive = _windowShown(WidgetsBinding.instance.lifecycleState);
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addEarlyKeyEventHandler(_onKeyEvent);
    _restorePinned();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    final audio = context.read<AudioController>();
    if (_audio != audio) {
      _audio?.removeListener(_syncIdleState);
      _audio = audio;
      audio.addListener(_syncIdleState);
    }
    _syncIdleState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = _windowShown(state);
    _syncIdleState();
  }

  /// Unlike the TV, a desktop window goes `inactive` whenever another app
  /// takes focus while it stays on screen — exactly when an idle player
  /// should keep showing just the artwork. Only a hidden window counts as away.
  static bool _windowShown(AppLifecycleState? state) =>
      state == null ||
      state == AppLifecycleState.resumed ||
      state == AppLifecycleState.inactive;

  void _syncIdleState() {
    final enabled = _canIdle;
    if (_idleEnabled == enabled) return;
    _idleEnabled = enabled;
    _idleTimer?.cancel();
    if (!_appActive || !(_route?.isCurrent ?? false)) _wakePresses.clear();
    _showControls();
    if (enabled) _restartTimer();
  }

  void _restartTimer() {
    _idleTimer?.cancel();
    if (!_canIdle) return;
    _idleTimer = Timer(_idleDelay, () {
      if (!mounted || !_canIdle) return;
      _previousFocus = FocusManager.instance.primaryFocus;
      setState(() => _controlsVisible = false);
      _idleFocus.requestFocus();
    });
  }

  void _showControls() {
    if (_controlsVisible && _previousFocus == null) return;
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_controlsVisible ||
          !_appActive ||
          !(_route?.isCurrent ?? false) ||
          _previousFocus == null) {
        return;
      }
      final previous = _previousFocus;
      final target = previous != null &&
              previous.context != null &&
              previous.canRequestFocus &&
              previous.ancestors.contains(_idleFocus)
          ? previous
          : _rootFocus;
      target.requestFocus();
      _previousFocus = null;
    });
  }

  void _onActivity() {
    if (!_appActive || !(_route?.isCurrent ?? false)) return;
    _showControls();
    _restartTimer();
  }

  KeyEventResult _onKeyEvent(KeyEvent event) {
    if (!_appActive || !(_route?.isCurrent ?? false)) {
      _wakePresses.clear();
      return KeyEventResult.ignored;
    }
    // Swallow the entire wake gesture, including held-key repeats and key-up.
    if (_wakePresses.contains(event.physicalKey)) {
      if (event is KeyUpEvent) _wakePresses.remove(event.physicalKey);
      _onActivity();
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final waking = !_controlsVisible && _wakeKeys.contains(event.logicalKey);
    if (waking) _wakePresses.add(event.physicalKey);
    _onActivity();
    return waking ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _audio?.removeListener(_syncIdleState);
    FocusManager.instance.removeEarlyKeyEventHandler(_onKeyEvent);
    WidgetsBinding.instance.removeObserver(this);
    _rootFocus.dispose();
    _idleFocus.dispose();
    super.dispose();
  }

  Future<void> _restorePinned() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(FullNowPlayingView.queuePinnedPrefKey) ?? false;
    if (!saved || _queueTouched || !mounted) return;
    setState(() {
      _queuePinned = true;
      _queueOpen = true;
    });
  }

  void _openQueue() {
    setState(() {
      _queueTouched = true;
      _queueOpen = true;
    });
  }

  void _closeQueue() {
    final wasPinned = _queuePinned;
    setState(() {
      _queueTouched = true;
      _queueOpen = false;
      _queuePinned = false;
    });
    if (wasPinned) {
      unawaited(_savePinned(false));
    }
  }

  void _togglePin() {
    final next = !_queuePinned;
    setState(() {
      _queueTouched = true;
      _queuePinned = next;
      _queueOpen = true;
    });
    unawaited(_savePinned(next));
  }

  Future<void> _savePinned(bool pinned) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(FullNowPlayingView.queuePinnedPrefKey, pinned);
  }

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioController>();
    final lyricsController = context.watch<LyricsController?>();
    final track = audio.currentTrack;
    final visible = _controlsVisible;
    final overlayOpen = _queueOpen && !_queuePinned && visible;
    final docked = _queueOpen && _queuePinned && visible;
    final panelWidth = _QueuePanel.widthFor(MediaQuery.of(context).size.width);

    // This route takes focus away from the shell's shortcut handler, so the
    // transport keys (space, arrows) must be bound here as well.
    return Focus(
      focusNode: _rootFocus,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyUpEvent && isSpotlightShortcut(event)) {
          if (event is KeyDownEvent) {
            unawaited(
              showSpotlightModal(
                context,
                onBeforeNavigate: () => Navigator.of(context).maybePop(),
              ),
            );
          }
          return KeyEventResult.handled;
        }
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          // Escape backs out of the floating queue drawer first; a pinned
          // queue is part of the layout, so Escape exits the view directly.
          if (overlayOpen) {
            _closeQueue();
          } else {
            Navigator.of(context).maybePop();
          }
          return KeyEventResult.handled;
        }
        return handleTransportKey(context.read<AudioController>(), event);
      },
      child: Scaffold(
        backgroundColor: context.colors.base,
        // Any pointer input anywhere on the player counts as activity and
        // resets the idle timer that hides the chrome.
        body: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => _onActivity(),
          onPointerMove: (_) => _onActivity(),
          onPointerHover: (_) => _onActivity(),
          onPointerSignal: (_) => _onActivity(),
          child: MouseRegion(
            // The cursor hides with the chrome; any movement brings both back.
            cursor: visible ? MouseCursor.defer : SystemMouseCursors.none,
            child: Focus(
              focusNode: _idleFocus,
              skipTraversal: true,
              child: Stack(
                children: [
                  Positioned.fill(child: _BlurredArtworkBackdrop(track: track)),
                  SafeArea(
                    child: Column(
                      children: [
                        if (maybeReadHost(context)?.hasMacWindowChrome ?? false)
                          maybeReadHost(context)
                                  ?.windowDragAreaBuilder
                                  ?.call(const SizedBox(
                                      height: 28, width: double.infinity)) ??
                              const SizedBox(height: 28, width: double.infinity),
                        Expanded(
                          child: AnimatedPadding(
                            duration: Motion.medium,
                            curve: Motion.standard,
                            padding:
                                EdgeInsets.only(right: docked ? panelWidth : 0),
                            child: track == null
                                ? const _EmptyFullNowPlaying()
                                : _FullNowPlayingContent(
                                    audio: audio,
                                    queueOpen: _queueOpen,
                                    onToggleQueue:
                                        _queueOpen ? _closeQueue : _openQueue,
                                    lyricsOpen:
                                        lyricsController?.lyricsPreferred ??
                                            false,
                                    onToggleLyrics:
                                        lyricsController?.toggleLyricsPreferred,
                                    chromeVisible: visible,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Dim the player behind the unpinned queue drawer; tap anywhere
                  // off the panel to dismiss it. When pinned, the player stays
                  // bright and interactive beside the queue.
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: !overlayOpen,
                      child: GestureDetector(
                        onTap: _closeQueue,
                        child: AnimatedOpacity(
                          opacity: overlayOpen ? 1 : 0,
                          duration: Motion.medium,
                          curve: Motion.standard,
                          child: const ColoredBox(color: Color(0x66000000)),
                        ),
                      ),
                    ),
                  ),
                  ExcludeFocus(
                    excluding: !visible,
                    child: IgnorePointer(
                      ignoring: !visible,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: AnimatedSlide(
                          offset: _queueOpen && visible
                              ? Offset.zero
                              : const Offset(1, 0),
                          duration: Motion.medium,
                          curve: Motion.standard,
                          child: _QueuePanel(
                            audio: audio,
                            pinned: _queuePinned,
                            onTogglePin: _togglePin,
                            onClose: _closeQueue,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyFullNowPlaying extends StatelessWidget {
  const _EmptyFullNowPlaying();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const _TopChrome(albumTitle: 'Now Playing'),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.music_note_rounded,
                size: 56,
                color: context.colors.textSecondary,
              ),
              const SizedBox(height: 18),
              Text(
                'Nothing playing',
                style:
                    PlayerTheme.display(44, color: context.colors.textPrimary),
              ),
              const SizedBox(height: 18),
              TextButton.icon(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                label: const Text('Close'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Full-player artwork never displays larger than this, so it is decoded at
/// this size once and scaled to fit.
const double _artworkDecodeSize = 560;

class _FullNowPlayingContent extends StatelessWidget {
  const _FullNowPlayingContent({
    required this.audio,
    required this.queueOpen,
    required this.onToggleQueue,
    required this.lyricsOpen,
    required this.chromeVisible,
    this.onToggleLyrics,
  });

  final AudioController audio;
  final bool queueOpen;
  final VoidCallback onToggleQueue;
  final bool lyricsOpen;

  /// False once the player has idled out: everything except the artwork,
  /// title and artist fades away.
  final bool chromeVisible;
  final VoidCallback? onToggleLyrics;

  void _showContextMenu(BuildContext context, Offset position, Track track) {
    showTrackContextMenu(
      context,
      position,
      track,
      onOpenAlbum: () {
        final navigator = context.read<PlayerNavigator>();
        Navigator.of(context).pop();
        navigator.openAlbum(track.albumId!);
      },
    );
  }

  Widget _buildArtwork(
    BuildContext context,
    Track track, {
    required double maxSize,
    double borderRadius = PlayerTheme.coverRadius * 1.5,
  }) {
    final client = context.read<ConnectionController>().client;
    return LayoutBuilder(
      builder: (context, artBox) {
        final artSize = math.min(
          math.min(artBox.maxWidth, artBox.maxHeight),
          maxSize,
        );
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onSecondaryTapDown: (details) => _showContextMenu(
            context,
            details.globalPosition,
            track,
          ),
          child: AnimatedSwitcher(
            duration: Motion.slow,
            switchInCurve: Motion.standard,
            switchOutCurve: Motion.standard,
            transitionBuilder: Motion.fadeScale,
            child: Container(
              key: ValueKey(track.albumId ?? track.id),
              width: artSize,
              height: artSize,
              // Decode once at the largest size and scale down, so the
              // lyrics morph and window resizes never trigger a re-decode.
              child: FittedBox(
                child: Artwork(
                  client: client,
                  albumId: track.albumId,
                  songId: track.albumId == null ? track.id : null,
                  thumbnail: false,
                  size: _artworkDecodeSize,
                  borderRadius:
                      borderRadius * _artworkDecodeSize / math.max(artSize, 1),
                  iconScale: 0.34,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTrackHeader(
    BuildContext context,
    Track track, {
    required double titleSize,
    required double artistSize,
    double iconSize = 26,
    bool showActions = true,

    /// Set beside the cover: flush left, with the album under the artist.
    bool besideCover = false,
    double artistGap = 14,
    int titleLines = 2,
  }) {
    final align = besideCover ? TextAlign.start : TextAlign.center;
    // Pop this route before navigating so the album or artist view isn't
    // hidden underneath the fullscreen player.
    void pop() => Navigator.of(context).pop();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) => _showContextMenu(
        context,
        details.globalPosition,
        track,
      ),
      child: AnimatedSwitcher(
        duration: Motion.medium,
        switchInCurve: Motion.standard,
        transitionBuilder: Motion.fadeSlideUp,
        layoutBuilder: (current, previous) => Stack(
          alignment:
              besideCover ? AlignmentDirectional.bottomStart : Alignment.center,
          children: [...previous, if (current != null) current],
        ),
        child: Column(
          key: ValueKey(track.id),
          crossAxisAlignment: besideCover
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            TrackTitleLink(
              title: track.title,
              albumId: track.albumId,
              textAlign: align,
              onBeforeNavigate: pop,
              maxLines: titleLines,
              style: PlayerTheme.display(titleSize,
                  color: context.colors.textPrimary),
            ),
            SizedBox(height: artistGap),
            ArtistCreditLinks(
              name: track.artist,
              textAlign: align,
              onBeforeNavigate: pop,
              style: TextStyle(
                color: besideCover
                    ? context.colors.textPrimary
                    : context.colors.textSecondary,
                fontSize: artistSize,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (besideCover && track.albumTitle != null)
              AlbumLink(
                title: track.albumTitle!,
                albumId: track.albumId,
                onBeforeNavigate: pop,
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: artistSize * 0.75,
                ),
              ),
            _ChromeFade(
              visible: showActions,
              alignment: besideCover ? Alignment.topLeft : Alignment.topCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: besideCover
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  SizedBox(height: besideCover ? 12 : 4),
                  // Beside the cover, pull the first icon's padding back so
                  // its glyph sits on the title's left edge.
                  Transform.translate(
                    offset: Offset(besideCover ? -8 : 0, 0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LikedSongButton(track: track, iconSize: iconSize),
                        PlaylistsButton(track: track, iconSize: iconSize),
                        if (context.watch<LyricsController?>()?.hasLyrics ??
                            false)
                          TransportToggle(
                            tooltip: 'Lyrics',
                            icon: Icons.lyrics_outlined,
                            size: iconSize,
                            active: lyricsOpen,
                            onPressed: onToggleLyrics,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final track = audio.currentTrack!;
    final lyricsController = context.watch<LyricsController?>();
    // Lyrics count as chrome: when the player idles out, only the artwork,
    // title and artist remain.
    final lyricsActive =
        chromeVisible && (lyricsController?.isLyricsActive ?? false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compactHeight = constraints.maxHeight < 720;
        final wide = constraints.maxWidth >= 900;

        final Widget contentArea;
        if (wide) {
          // The record and its label side by side: the cover on the left,
          // the title set large beside it, resting on the cover's bottom
          // edge. With lyrics on, one eased value shrinks the title into a
          // header and the lyrics rise to fill the column under it; the
          // cover stays put.
          final restTitle = (constraints.maxWidth * 0.076)
              .clamp(64.0, compactHeight ? 88.0 : 118.0);
          contentArea = Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final cover = math.min(
                  _artworkDecodeSize,
                  math.min(box.maxHeight, box.maxWidth * 0.44),
                );
                return TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: lyricsActive ? 1 : 0),
                  duration: Motion.reveal,
                  curve: Motion.emphasized,
                  child: const LyricsView(compact: false, flush: true),
                  builder: (context, t, lyricsView) {
                    double lerp(double a, double b) => a + (b - a) * t;
                    int flex(double f) => math.max(1, (f * 1000).round());
                    final reveal =
                        const Interval(0.35, 1, curve: Curves.easeOut)
                            .transform(t);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 44),
                      child: Row(
                        children: [
                          _buildArtwork(context, track, maxSize: cover),
                          const SizedBox(width: 64),
                          Expanded(
                            child: Padding(
                              // At rest the label's foot lines up with the
                              // cover's.
                              padding: EdgeInsets.only(
                                bottom: lerp((box.maxHeight - cover) / 2, 0),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (t < 1) Spacer(flex: flex(1 - t)),
                                  _buildTrackHeader(
                                    context,
                                    track,
                                    besideCover: true,
                                    titleSize: lerp(restTitle, 44),
                                    titleLines: t < 0.5 ? 3 : 2,
                                    artistGap: lerp(22, 10),
                                    artistSize: lerp(22, 16),
                                    iconSize: 24,
                                    showActions: chromeVisible,
                                  ),
                                  if (t > 0)
                                    Expanded(
                                      flex: flex(t),
                                      child: Opacity(
                                        opacity: reveal,
                                        child: lyricsView,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          );
        } else {
          contentArea = Expanded(
            child: Column(
              children: [
                Expanded(
                  child: AnimatedSwitcher(
                    duration: Motion.step,
                    switchInCurve: Motion.standard,
                    switchOutCurve: Motion.standard,
                    transitionBuilder: Motion.fadeScale,
                    child: lyricsActive
                        ? const LyricsView(
                            key: ValueKey('lyrics'),
                            compact: false,
                          )
                        : Center(
                            key: const ValueKey('artwork'),
                            child: _buildArtwork(
                              context,
                              track,
                              maxSize: 560.0,
                            ),
                          ),
                  ),
                ),
                SizedBox(height: compactHeight ? 20 : 30),
                _buildTrackHeader(
                  context,
                  track,
                  titleSize: compactHeight ? 44 : 60,
                  artistSize: compactHeight ? 15 : 18,
                  showActions: chromeVisible,
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            _ChromeFade(
              visible: chromeVisible,
              alignment: Alignment.bottomCenter,
              child: _TopChrome(albumTitle: track.albumTitle ?? 'Now Playing'),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  28,
                  compactHeight ? 12 : 20,
                  28,
                  compactHeight ? 16 : 24,
                ),
                child: Column(
                  children: [
                    contentArea,
                    SizedBox(height: compactHeight ? 16 : 24),
                    _ChromeFade(
                      visible: chromeVisible,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 840),
                        child: Column(
                          children: [
                            _FullTransportControls(audio: audio),
                            const SizedBox(height: 18),
                            _FullSeekBar(
                              audio: audio,
                              queueOpen: queueOpen,
                              onToggleQueue: onToggleQueue,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Fades [child] out and collapses its height in sync when the fullscreen
/// player idles down to just the artwork, title and artist (matching the TV
/// player), so the remaining content recentres smoothly instead of jumping.
class _ChromeFade extends StatelessWidget {
  const _ChromeFade({
    required this.visible,
    required this.child,
    this.alignment = Alignment.topCenter,
  });

  final bool visible;
  final Widget child;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: visible ? 1.0 : 0.0),
      duration: Motion.medium,
      curve: Curves.easeInOut,
      // Collapse the chrome's space along with its fade so the remaining
      // artwork and labels centre.
      // Clip only while collapsing, so the play button's glow isn't cut off.
      builder: (_, heightFactor, child) => ClipRect(
        clipBehavior: heightFactor < 1 ? Clip.hardEdge : Clip.none,
        child: Align(
          alignment: alignment,
          heightFactor: heightFactor,
          child: child,
        ),
      ),
      child: ExcludeSemantics(
        excluding: !visible,
        child: ExcludeFocus(
          excluding: !visible,
          child: IgnorePointer(
            ignoring: !visible,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: Motion.medium,
              curve: Curves.easeInOut,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _TopChrome extends StatelessWidget {
  const _TopChrome({required this.albumTitle});

  final String albumTitle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: IconButton(
                tooltip: 'Collapse',
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
                color: context.colors.textPrimary,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 88),
            child: Text(
              albumTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style:
                  PlayerTheme.heading(15, color: context.colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _FullTransportControls extends StatelessWidget {
  const _FullTransportControls({required this.audio});

  final AudioController audio;

  @override
  Widget build(BuildContext context) {
    final hasTrack = audio.currentTrack != null;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TransportToggle(
          tooltip: 'Shuffle',
          icon: Icons.shuffle_rounded,
          size: 24,
          active: audio.shuffle,
          onPressed: hasTrack ? audio.toggleShuffle : null,
        ),
        const SizedBox(width: 18),
        IconButton(
          tooltip: 'Previous',
          icon: const Icon(Icons.skip_previous_rounded, size: 34),
          color: context.colors.textPrimary,
          onPressed: hasTrack ? audio.previous : null,
        ),
        const SizedBox(width: 18),
        _FullPlayPauseButton(audio: audio),
        const SizedBox(width: 18),
        IconButton(
          tooltip: 'Next',
          icon: const Icon(Icons.skip_next_rounded, size: 34),
          color: context.colors.textPrimary,
          onPressed: hasTrack && audio.hasNext ? audio.next : null,
        ),
        const SizedBox(width: 18),
        TransportToggle(
          tooltip: 'Repeat',
          icon: audio.repeat == PlayerRepeatMode.one
              ? Icons.repeat_one_rounded
              : Icons.repeat_rounded,
          size: 24,
          active: audio.repeat != PlayerRepeatMode.off,
          onPressed: hasTrack ? audio.cycleRepeat : null,
        ),
      ],
    );
  }
}

class _FullPlayPauseButton extends StatelessWidget {
  const _FullPlayPauseButton({required this.audio});

  final AudioController audio;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasTrack = audio.currentTrack != null;
    final Widget inner;
    if (audio.isLoading) {
      inner = SizedBox(
        key: const ValueKey('loading'),
        width: 32,
        height: 32,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation<Color>(scheme.onPrimary),
        ),
      );
    } else {
      inner = Icon(
        audio.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
        key: ValueKey(audio.isPlaying ? 'pause' : 'play'),
        color: scheme.onPrimary,
        size: 38,
      );
    }

    return Material(
      color: hasTrack ? scheme.primary : scheme.primary.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(PlayerTheme.tileRadius + 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(PlayerTheme.tileRadius + 2),
        mouseCursor:
            hasTrack ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onTap: hasTrack ? audio.togglePlayPause : null,
        child: SizedBox(
          width: 76,
          height: 60,
          child: Center(
            child: AnimatedSwitcher(
              duration: Motion.fast,
              transitionBuilder: Motion.fadeScale,
              child: inner,
            ),
          ),
        ),
      ),
    );
  }
}

class _FullSeekBar extends StatelessWidget {
  const _FullSeekBar({
    required this.audio,
    required this.queueOpen,
    required this.onToggleQueue,
  });

  final AudioController audio;
  final bool queueOpen;
  final VoidCallback onToggleQueue;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 13,
      color: context.colors.textSecondary,
      fontFeatures: PlayerTheme.tabular,
    );

    return Row(
      children: [
        const AriamiConnectButton(),
        SizedBox(
          width: 54,
          child: PositionClock(audio: audio, style: style),
        ),
        const SizedBox(width: 14),
        // The transport bar's band, drawn thin: the same fill and edge.
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: ColoredBox(
              color: context.colors.border,
              child: SizedBox(height: 10, child: ProgressBand(audio: audio)),
            ),
          ),
        ),
        const SizedBox(width: 14),
        SizedBox(
          width: 54,
          child: Text(
            formatClockDuration(audio.duration ?? Duration.zero),
            style: style,
          ),
        ),
        TransportToggle(
          tooltip: 'Up next',
          icon: Icons.queue_music_rounded,
          active: queueOpen,
          onPressed: onToggleQueue,
        ),
        VolumeControl(audio: audio, sliderWidth: 100, iconSize: 22),
      ],
    );
  }
}

/// The slide-in queue drawer for the fullscreen player: the upcoming tracks,
/// with tap-to-play and drag-to-reorder, matching the player's simple theme.
class _QueuePanel extends StatelessWidget {
  const _QueuePanel({
    required this.audio,
    required this.pinned,
    required this.onTogglePin,
    required this.onClose,
  });

  final AudioController audio;
  final bool pinned;
  final VoidCallback onTogglePin;
  final VoidCallback onClose;

  static double widthFor(double screenWidth) =>
      math.min(400.0, screenWidth * 0.88);

  @override
  Widget build(BuildContext context) {
    final width = widthFor(MediaQuery.of(context).size.width);
    final upcoming = audio.upcoming;
    final accent = Theme.of(context).colorScheme.secondary;

    return AnimatedContainer(
      duration: Motion.medium,
      curve: Motion.standard,
      width: width,
      height: double.infinity,
      decoration: BoxDecoration(
        color: pinned
            ? context.colors.popover.withValues(alpha: 0.72)
            : context.colors.popover,
        border: Border(left: BorderSide(color: context.colors.border)),
      ),
      child: SafeArea(
        left: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Tooltip(
                      message: queueSelectionHint,
                      child: Text(
                        'Up next',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PlayerTheme.heading(18,
                            color: context.colors.textPrimary),
                      ),
                    ),
                  ),
                  if (upcoming.length > 1)
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: audio.reshuffleUpcoming,
                      child: const Text('Reshuffle'),
                    ),
                  if (upcoming.isNotEmpty)
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: audio.clearUpcoming,
                      child: const Text('Clear'),
                    ),
                  IconButton(
                    tooltip: pinned ? 'Unpin queue' : 'Pin queue',
                    icon: Icon(
                      pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                      size: 20,
                    ),
                    color: pinned ? accent : context.colors.textSecondary,
                    onPressed: onTogglePin,
                  ),
                  IconButton(
                    tooltip: 'Close queue',
                    icon: const Icon(Icons.close_rounded, size: 22),
                    color: context.colors.textSecondary,
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            Expanded(
              child: upcoming.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Nothing queued.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.colors.textSecondary),
                        ),
                      ),
                    )
                  : QueueList(
                      keyPrefix: 'full-queue',
                      maxRows: _kMaxQueueRows,
                      style: QueueListStyle.fullScreen,
                      onBeforeNavigate: () => Navigator.of(context).pop(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

const int _kMaxQueueRows = 100;

/// The fullscreen player's backdrop: the sleeve's two-ink ground, like the
/// rest of the player. Only when the user has turned on the moving backdrop or the
/// music visualizer does it become the playing artwork, blown up and blurred
/// over the ambient glow — kicks flash over the top, as the art and scrim
/// would otherwise hide them.
class _BlurredArtworkBackdrop extends StatelessWidget {
  const _BlurredArtworkBackdrop({required this.track});

  final Track? track;

  @override
  Widget build(BuildContext context) {
    final client = context.read<ConnectionController>().client;
    final colors = context.colors;
    final track = this.track;
    final key = track?.albumId ?? track?.id;
    final moving = movingBackdrop(context);
    final visualizer = musicVisualizer(context);
    if (!moving && !visualizer) {
      return DecoratedBox(
        decoration: BoxDecoration(gradient: colors.groundGradient),
      );
    }
    return AmbientBackdrop(
      layoutSeed: (key ?? '').hashCode,
      moving: moving,
      levels: AudioLevelMeter.instance,
      visualizer: visualizer,
      foreground: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 900),
            child: track == null || client == null
                ? const SizedBox.shrink()
                // Expand: AnimatedSwitcher's stack hands its children loose
                // constraints.
                : SizedBox.expand(
                    key: ValueKey(key),
                    child: BlurredCover(Artwork.thumbnailOf(track, client)),
                  ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colors.base.withValues(alpha: 0.25),
                  colors.base.withValues(alpha: 0.7),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
