import 'dart:async';

import 'package:ariami_core/models/connect_models.dart' show AriamiConnectFeature;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/ariami_connect_controller.dart';
import '../services/audio/audio_level_meter.dart';
import '../services/audio/equalizer_service.dart';
import '../services/audio/gapless_playback_service.dart';
import '../services/audio_controller.dart';
import '../services/connection_controller.dart';
import '../services/library_controller.dart';
import '../services/listening_stats_controller.dart';
import '../services/lyrics_controller.dart';
import '../services/media_controls_service.dart';
import '../services/music_discovery_controller.dart';
import '../services/player_api_client.dart';
import '../services/player_host.dart';
import '../services/player_navigator.dart';
import '../services/search_settings_service.dart';
import '../services/theme_controller.dart';
import '../theme/player_theme.dart';
import '../widgets/ambient_backdrop.dart';
import '../widgets/artwork_image_provider.dart';
import 'connect_view.dart';
import 'connection_surface.dart';
import 'player_shell.dart';
import 'register_view.dart';
import 'sign_in_view.dart';

/// Root of the music-player experience.
///
/// Owns the long-lived controllers, wires them together (connection → client →
/// library/audio/theme), and swaps between connect / sign-in / player surfaces
/// based on the connection stage. Everything below is themed by
/// [ThemeController].
class PlayerRoot extends StatefulWidget {
  const PlayerRoot({super.key, required this.host, this.localServerPort});

  final PlayerHost host;

  /// When set (server + client mode), the player connects to the embedded
  /// local server on this port instead of restoring a remote target. The
  /// server admin dashboard is then available inside Settings.
  final int? localServerPort;

  @override
  State<PlayerRoot> createState() => _PlayerRootState();
}

class _PlayerRootState extends State<PlayerRoot> {
  late final ConnectionController _connection;
  late final LibraryController _library;
  late final AudioController _audio;
  final EqualizerService _equalizer = EqualizerService();
  final GaplessPlaybackService _gapless = GaplessPlaybackService();
  final AriamiConnectController _connect = AriamiConnectController();
  final ThemeController _theme = ThemeController();
  final PlayerNavigator _navigator = PlayerNavigator();
  final SearchQueryHolder _searchQuery = SearchQueryHolder();
  final MediaControlsService _mediaControls = MediaControlsService();
  late final ListeningStatsController _stats;
  final LyricsController _lyrics = LyricsController();
  late final MusicDiscoveryController _discovery;
  late final AppLifecycleListener _lifecycle;

  bool _wasConnected = false;
  bool _offlineDataLoaded = false;
  PlayerApiClient? _attachedClient;
  String? _lastTrackId;

  // One-time "setup finished" greeting. It only arms when this session went
  // through a setup surface (first-run pairing here, or the server wizard via
  // DesktopSetupSession), so normal launches never replay it — and it only
  // shows once the connection is actually confirmed.
  bool _sawInteractiveSetup = false;
  bool _celebrationShown = false;
  bool _celebrationVisible = false;

  @override
  void initState() {
    super.initState();
    final host = widget.host;
    _connection = ConnectionController(host: host);
    _library = LibraryController(
      searchSettings: SearchSettingsService(),
      snapshotStore: host.librarySnapshotStore,
    );
    _audio = AudioController(host: host);
    _stats = ListeningStatsController(
      outboxStore: host.listeningOutboxStore,
      clientKind: host.statsClientKind,
    );
    _discovery = MusicDiscoveryController(
      readLegacyApiKey: host.readLegacyDiscoveryApiKey,
    );
    _lifecycle = AppLifecycleListener(
      onHide: kIsWeb ? null : PaintingBinding.instance.imageCache.clear,
    );
    _equalizer.configure(host.equalizerBackend);
    AudioLevelMeter.instance.configure(host.levelMeterBackend);
    ArtworkImageProvider.cacheStore = host.artworkCacheStore;

    final downloads = host.downloads;
    if (downloads != null) {
      _audio.localFileResolver = downloads.localPathFor;
      _audio.downloadedFileResolver = downloads.localPathForAtLeast;
    }
    PaintingBinding.instance.imageCache.maximumSize = 2000;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 64 << 20;
    _connection.addListener(_onConnectionChanged);
    _library.addListener(_onLibraryChanged);
    _audio.addListener(_onAudioChanged);
    _mediaControls.start(_audio, backend: host.mediaControlsBackend);
    host.discord?.start(_audio);
    _stats.attach(_audio);
    _connect.onListeningStatsUpdated = _stats.onRemoteStatsUpdated;
    _connect.onPinsChanged = _library.refreshPins;
    _connect.onHiddenChanged = _library.refreshHidden;
    _connect.onCurationChanged = _library.refreshCuration;
    _connect.onPlaylistEditsChanged = _library.refreshPlaylistEdits;
    _connect.onArtistImagesChanged = _library.refreshArtistImages;
    _connect.onSyncTokenAdvanced = _library.onSyncTokenAdvanced;
    _lyrics.attach(
      audio: _audio,
      downloads: downloads,
      client: _attachedClient,
    );
    _discovery.attach(
      connection: _connection,
      library: _library,
      stats: _stats,
    );
    _stats.onReset = () => unawaited(_discovery.clearCache());
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final host = widget.host;
    final localPort = widget.localServerPort;
    final sameOriginUri = host.sameOriginUri;
    final pendingSignIn =
        localPort != null ? host.takePendingLocalSignIn?.call() : null;
    await Future.wait([
      _theme.load(),
      _equalizer.initialize(),
      _gapless.initialize(),
      if (host.discord != null) host.discord!.initialize(),
      if (sameOriginUri != null)
        _connection.connectSameOrigin(sameOriginUri)
      else if (localPort != null)
        _connection.connectLocal(
          port: localPort,
          initialUsername: pendingSignIn?.username,
          initialPassword: pendingSignIn?.password,
        )
      else
        _connection.autoConnect(),
    ]);
  }

  void _onConnectionChanged() {
    final host = widget.host;
    final stage = _connection.stage;
    final connected = stage == ConnectionStage.connected;

    if (stage == ConnectionStage.idle ||
        stage == ConnectionStage.error ||
        stage == ConnectionStage.needsRegistration) {
      _sawInteractiveSetup = true;
    }
    if (connected && !_celebrationShown) {
      final justCompletedSetup = host.takeSetupJustCompleted?.call() ?? false;
      if (justCompletedSetup ||
          (_sawInteractiveSetup && host.setupCompletionOverlayBuilder != null)) {
        _celebrationShown = true;
        if (mounted) setState(() => _celebrationVisible = true);
      }
    }
    final offlineActive = _connection.isOfflineActive;
    _audio.setOfflinePlayback(offlineActive);

    if (connected) {
      _offlineDataLoaded = false;
      final client = _connection.client;
      final firstAttach = !_wasConnected;
      if (client == null || identical(client, _attachedClient)) {
        _wasConnected = true;
        unawaited(_library.syncPendingPlaylistEdits());
        return;
      }

      _wasConnected = true;
      _attachedClient = client;
      _audio.setLocalPlayback(_connection.isLocalServer);
      _audio.serverFileResolver =
          _connection.isLocalServer ? host.serverFileResolver : null;
      host.onAttachedClientChanged?.call(client);
      final serverIdentity =
          _connection.serverInfo?.stableKey ?? client.baseUrl;
      ArtworkImageProvider.resetSessionState();
      ArtworkImageProvider.cacheScope =
          '$serverIdentity:${_connection.serverInfo?.port ?? 8080}';
      _library.attach(
        client,
        accountKey:
            '$serverIdentity:${_connection.serverInfo?.port ?? 8080}|${_connection.username ?? ''}',
      );
      _audio.attach(client);
      _theme.attach(client);
      _stats.attachClient(
        client,
        accountKey: '${client.baseUrl}|${_connection.username ?? ''}',
      );
      host.downloads?.attach(
        client,
        accountKey: '${client.baseUrl}|${_connection.username ?? ''}',
      );
      _lyrics.updateClient(client);
      _library.load();
      _mediaControls.updateClient(client);
      if (firstAttach) {
        _audio.restore();
      }
      _connect.attach(
        _connection,
        _audio,
        clientType: host.clientType,
        supportedFeatures: host.cast != null
            ? const <String>{AriamiConnectFeature.preserveCastHandoff}
            : const <String>{},
      );
    } else if (offlineActive) {
      if (!_wasConnected && !_offlineDataLoaded) {
        _offlineDataLoaded = true;
        unawaited(_loadOfflineData());
      }
      return;
    } else if (stage == ConnectionStage.connecting &&
        (_wasConnected || _offlineDataLoaded)) {
      return;
    } else if (_wasConnected || _offlineDataLoaded) {
      _wasConnected = false;
      _offlineDataLoaded = false;
      _attachedClient = null;
      _audio.serverFileResolver = null;
      host.onAttachedClientChanged?.call(null);
      _audio.clear();
      _connect.detach();
      _audio.attach(null);
      _library.attach(null);
      _stats.attachClient(null);
      host.downloads?.attach(null);
      _lyrics.updateClient(null);
      _mediaControls.updateClient(null);
    }
  }

  Future<void> _loadOfflineData() async {
    await widget.host.downloads?.attachOffline();
    await _library.loadOfflineSnapshot();
    await _audio.restore();
  }

  void _onAudioChanged() {
    widget.host.onAudioStateChanged?.call(
      PlayerAudioState(
        isPlayingHere: _audio.isPlayingHere,
        isPlaying: _audio.isPlaying,
        currentTrack: _audio.currentTrack,
        localIsPlaying: _audio.localIsPlaying,
        localCurrentTrack: _audio.localCurrentTrack,
        isOfflinePlayback: _audio.isOfflinePlayback,
      ),
    );
    final id = _audio.currentTrack?.id;
    if (id != _lastTrackId) {
      _lastTrackId = id;
      _theme.onTrackChanged(_audio.currentTrack);
    }
  }

  void _onLibraryChanged() {
    final albums = _library.albums;
    final songs = _library.songs;
    _stats.updateAlbumCatalog(albums);
    widget.host.downloads?.refreshAlbumMetadata(albums: albums, tracks: songs);
  }

  @override
  void dispose() {
    _connection.removeListener(_onConnectionChanged);
    _library.removeListener(_onLibraryChanged);
    _audio.removeListener(_onAudioChanged);
    widget.host.onAttachedClientChanged?.call(null);
    widget.host.onAudioStateChanged?.call(
      const PlayerAudioState(isPlayingHere: false, isPlaying: false),
    );
    _lifecycle.dispose();
    _mediaControls.dispose();
    widget.host.discord?.dispose();
    _discovery.dispose();
    _connection.dispose();
    _library.dispose();
    _connect.dispose();
    _audio.dispose();
    _theme.dispose();
    _navigator.dispose();
    _searchQuery.dispose();
    _stats.dispose();
    widget.host.downloads?.dispose();
    _lyrics.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<PlayerHost>.value(value: widget.host),
        Provider<PlayerHost?>.value(value: widget.host),
        ChangeNotifierProvider.value(value: _connection),
        ChangeNotifierProvider.value(value: _library),
        ChangeNotifierProvider.value(value: _library.searchSettings),
        ChangeNotifierProvider.value(value: _audio),
        ChangeNotifierProvider.value(value: _equalizer),
        ChangeNotifierProvider.value(value: _gapless),
        ChangeNotifierProvider.value(value: _connect),
        ChangeNotifierProvider.value(value: _theme),
        ChangeNotifierProvider.value(value: _navigator),
        ChangeNotifierProvider.value(value: _stats),
        ChangeNotifierProvider<PlayerDownloadsBridge?>.value(
          value: widget.host.downloads,
        ),
        ChangeNotifierProvider.value(value: _lyrics),
        ChangeNotifierProvider.value(value: _discovery),
        ChangeNotifierProvider<PlayerDiscordBridge?>.value(
          value: widget.host.discord,
        ),
        Provider<SearchQueryHolder>.value(value: _searchQuery),
      ],
      child: Consumer<ThemeController>(
        builder: (context, theme, _) {
          // The pre-connection surfaces are designed on black, so they ignore
          // the saved appearance and always render the dark setup theme —
          // otherwise signing out drops the connect form into the last session's light
          // or colour-seeded theme. Selected (not watched) so this only
          // rebuilds when the answer actually flips.
          final forceDark = context.select<ConnectionController, bool>(
            (connection) => _isPreConnectionSurface(connection.stage),
          );
          final data = forceDark
              ? PlayerTheme.setup()
              : theme.resolveTheme(MediaQuery.platformBrightnessOf(context));
          return AnimatedTheme(
            data: data,
            duration: const Duration(milliseconds: 400),
            child: Material(
              color: data.scaffoldBackgroundColor,
              child: Stack(
                children: [
                  // One backdrop behind every surface, so it stays put while
                  // the connection flow steps between forms and into the
                  // player.
                  const Positioned.fill(child: _Backdrop()),
                  Positioned.fill(
                    child: Consumer<ConnectionController>(
                      builder: (context, connection, _) {
                        // Owns the motion between connection surfaces, and
                        // the stage it hands back may lag the live one while
                        // it debounces the progress spinner — so the body is
                        // built from that stage, never from connection.stage.
                        return ConnectionSurface(
                          stage: connection.stage,
                          builder: (stage) => _buildBody(connection, stage),
                        );
                      },
                    ),
                  ),
                  // Covers the player while it finishes loading after a
                  // freshly completed setup, then reveals it.
                  if (_celebrationVisible &&
                      widget.host.setupCompletionOverlayBuilder != null)
                    Positioned.fill(
                      child: widget.host.setupCompletionOverlayBuilder!(
                        context,
                        () => setState(() => _celebrationVisible = false),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Whether a stage renders an auth / connect surface rather than the player.
  ///
  /// These screens are part of the setup look and stay on black. `reconnecting`
  /// and `offline` are deliberately absent: they can render the full player
  /// shell, which must keep the user's chosen appearance.
  static bool _isPreConnectionSurface(ConnectionStage stage) {
    switch (stage) {
      case ConnectionStage.initializing:
      case ConnectionStage.idle:
      case ConnectionStage.connecting:
      case ConnectionStage.needsAuth:
      case ConnectionStage.needsRegistration:
      case ConnectionStage.error:
        return true;
      case ConnectionStage.reconnecting:
      case ConnectionStage.offline:
      case ConnectionStage.connected:
        return false;
    }
  }

  Widget _buildBody(ConnectionController connection, ConnectionStage stage) {
    final Widget body;
    switch (stage) {
      case ConnectionStage.initializing:
        body = const _ConnectingView(restoring: true);
      case ConnectionStage.idle:
        body = const ConnectView();
      case ConnectionStage.connecting:
        body = const _ConnectingView();
      case ConnectionStage.reconnecting:
        // Automatic offline mode: keep the player usable on downloaded music
        // while retries run. The blocking screen only remains for sessions
        // with nothing to show (no library snapshot / no downloads).
        body = ListenableBuilder(
          listenable: _library,
          builder: (context, _) => _library.hasContent
              ? const PlayerShell()
              : const _ReconnectingView(),
        );
      case ConnectionStage.needsAuth:
        body = const SignInView();
      case ConnectionStage.needsRegistration:
        body = const RegisterView();
      case ConnectionStage.error:
        body = connection.isSameOriginWeb
            ? _SameOriginErrorView(
                message: connection.errorMessage,
                onRetry: () => unawaited(
                  connection.connectSameOrigin(widget.host.sameOriginUri!),
                ),
              )
            : const ConnectView();
      case ConnectionStage.offline:
        body = const PlayerShell();
      case ConnectionStage.connected:
        body = const PlayerShell();
    }

    final overlay = widget.host.setupOverlayBuilder?.call(context, connection);
    if (overlay == null) return body;
    return Stack(
      children: [
        Positioned.fill(child: body),
        overlay,
      ],
    );
  }
}

class _SameOriginErrorView extends StatelessWidget {
  const _SameOriginErrorView({required this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 52,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Could not reach Ariami server',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (message != null && message!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textSecondary),
                ),
              ],
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    // The player sits on the sleeve's two-ink ground unless the moving
    // background is on; the setup and connection screens always sit on the glow.
    final setup = context.select<ConnectionController, bool>(
      (connection) => _PlayerRootState._isPreConnectionSurface(connection.stage),
    );
    final glow = context.select<ThemeController, bool>((t) => t.movingBackdrop);
    if (!setup && !glow) {
      return DecoratedBox(
        decoration: BoxDecoration(gradient: context.colors.groundGradient),
      );
    }
    final seed = context.select<AudioController, int>((audio) {
      final track = audio.currentTrack;
      return (track?.albumId ?? track?.id ?? '').hashCode;
    });
    return AmbientBackdrop(
      layoutSeed: seed,
      moving: movingBackdrop(context),
      levels: AudioLevelMeter.instance,
    );
  }
}

class _ConnectingView extends StatelessWidget {
  const _ConnectingView({this.restoring = false});

  final bool restoring;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 20),
          Text(restoring
              ? 'Restoring your session…'
              : 'Connecting to your library…'),
        ],
      ),
    );
  }
}

class _ReconnectingView extends StatelessWidget {
  const _ReconnectingView();

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionController>();
    final colors = context.colors;
    final scheme = Theme.of(context).colorScheme;
    final serverName = connection.serverInfo?.name ?? 'Ariami server';
    final address = connection.reconnectingAddress ?? 'the saved address';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 58,
                color: scheme.primary,
              ),
              const SizedBox(height: 18),
              Text(
                'Lost connection to $serverName',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                'Retrying $address. The server machine may be off or asleep, '
                'the Ariami server may have stopped, or the network may have '
                'changed.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                      height: 1.45,
                    ),
              ),
              const SizedBox(height: 24),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: colors.surfaceHigh,
                  borderRadius: BorderRadius.circular(PlayerTheme.cardRadius),
                  border: Border.all(color: colors.border),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Reconnecting automatically...',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              ElevatedButton.icon(
                onPressed: connection.retryReconnectNow,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again now'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: connection.disconnect,
                icon: const Icon(Icons.dns_outlined),
                label: const Text('Choose another server'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
