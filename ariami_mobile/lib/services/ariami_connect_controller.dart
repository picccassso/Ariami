import 'dart:async';

import 'package:ariami_core/services/connect/connect_client.dart';
import 'package:ariami_core/services/connect/remote_playback.dart';
import 'package:ariami_core/models/connect_models.dart';
import 'package:flutter/foundation.dart';

import 'api/connection_service.dart';
import 'playback_manager.dart';
import 'stats/account_stats_service.dart';

class AriamiConnectController extends ChangeNotifier {
  static final AriamiConnectController _instance =
      AriamiConnectController._internal();
  factory AriamiConnectController() => _instance;
  AriamiConnectController._internal();

  final ConnectionService _connection = ConnectionService();
  AriamiConnectClient? _client;
  PlaybackManager? _playback;
  StreamSubscription<dynamic>? _serverSubscription;
  Timer? _staleStateTimer;
  String? _lastTrackId;
  bool _lastPlaying = false;
  String? _connectedBaseUrl;
  bool _started = false;
  bool _pendingLocalTakeover = false;
  int _generation = 0;

  List<AriamiConnectDevice> get devices =>
      _client?.devices ?? const <AriamiConnectDevice>[];
  AriamiConnectDevice? get activeDevice => _client?.activeDevice;
  String? get activeDeviceId => _client?.activeDeviceId;
  AriamiConnectDevice? get thisDevice => _client?.thisDevice;
  bool get isConnected => _client?.isConnected ?? false;
  bool get isThisDeviceActive => _client?.isThisDeviceActive ?? false;
  String? get errorMessage => _client?.errorMessage;

  Future<void> start(PlaybackManager playback) async {
    _playback = playback;
    _lastTrackId = playback.localCurrentSong?.id;
    _lastPlaying = playback.localIsPlaying;
    _pendingLocalTakeover = _lastPlaying && playback.localCurrentSong != null;
    if (!_started) {
      _started = true;
      _generation++;
      playback.addListener(_onPlaybackChanged);
      _serverSubscription = _connection.serverInfoStream.listen((_) {
        unawaited(_connectToCurrentEndpoint());
      });
      _staleStateTimer = Timer.periodic(
        _staleCheckInterval,
        (_) => _repairStaleSocket(),
      );
    }
    await _connectToCurrentEndpoint();
  }

  Future<void> _connectToCurrentEndpoint() async {
    final generation = _generation;
    final playback = _playback;
    final info = _connection.serverInfo;
    if (playback == null || info == null || !_connection.isConnected) return;
    if (_connectedBaseUrl == info.baseUrl && _client != null) return;
    final old = _client;
    _client = null;
    await old?.dispose();
    if (generation != _generation || _playback == null) return;
    _connectedBaseUrl = info.baseUrl;
    final deviceId = await _connection.getCurrentDeviceId();
    final deviceName = await _connection.getCurrentDeviceName();
    if (generation != _generation || _playback == null) return;
    if (kDebugMode) {
      AriamiConnectClient.logger =
          (message) => debugPrint('[Connect] $message');
    }
    final client = AriamiConnectClient(
      deviceId: deviceId,
      deviceName: deviceName,
      clientType: 'mobile',
      snapshotProvider: () => playback.connectSnapshot,
      applySnapshot: playback.applyConnectSnapshot,
      handleCommand: _handleCommand,
      pauseForTransfer: playback.pauseLocal,
      supportedCommands: PlaybackManager.connectSupportedCommands,
      onChanged: _onClientChanged,
      onAuthenticationRequired: () =>
          unawaited(_connection.handleSessionExpired()),
      // Stats pushes for this account arrive on the Connect socket; refresh
      // the account-wide view when another device uploads listening activity.
      onServerNotification: (_) =>
          unawaited(AccountStatsService().refreshSummary()),
    );
    _client = client;
    if (_pendingLocalTakeover) {
      _pendingLocalTakeover = false;
      client.requestLocalTakeover();
    }
    await client.connect(
      baseUrl: info.baseUrl,
      sessionToken: _connection.sessionToken,
    );
    if (generation != _generation) {
      await client.dispose();
      return;
    }
    notifyListeners();
  }

  void _onPlaybackChanged() {
    final playback = _playback;
    final client = _client;
    if (playback == null || (client?.isApplyingRemoteState ?? false)) {
      return;
    }
    // While mirroring another device there is no local playback worth
    // publishing; the mirror's own notifications must not look like takeovers.
    if (playback.isConnectRemoteActive) return;
    final trackId = playback.localCurrentSong?.id;
    final playing = playback.localIsPlaying;
    // Starting music locally is a takeover; a mere track change while paused
    // (e.g. queueing into an empty queue) is not.
    final activate = (playing && trackId != null && trackId != _lastTrackId) ||
        (playing && !_lastPlaying && !(client?.isThisDeviceActive ?? false));
    _lastTrackId = trackId;
    _lastPlaying = playing;
    if (!playing || trackId == null) {
      _pendingLocalTakeover = false;
      client?.cancelLocalTakeover();
    }
    if (activate) {
      // Publish takeovers immediately so the hub pauses the old device and
      // confirms this one as active before stale remote state can flash back.
      if (client == null) {
        _pendingLocalTakeover = true;
      } else {
        client.requestLocalTakeover();
      }
      return;
    }
    client?.publishState();
  }

  Future<void> _handleCommand(
      String command, Map<String, dynamic> arguments) async {
    await _playback?.handleConnectCommand(command, arguments);
  }

  /// Renames this phone across the account: the server persists the name and
  /// pushes the updated device list to every Ariami Connect client.
  void renameThisDevice(String name) => _client?.renameThisDevice(name);

  void _onClientChanged() {
    _syncRemoteMirror();
    notifyListeners();
  }

  /// Feeds the playback manager a mirror of the active device's playback
  /// whenever another device owns the session, and clears it otherwise.
  void _syncRemoteMirror() {
    final playback = _playback;
    if (playback == null) return;
    final client = _client;
    final active = client?.activeDevice;
    final snapshot = client?.remoteSnapshot;
    if (client == null ||
        !client.isConnected ||
        client.isThisDeviceActive ||
        client.hasPendingLocalTakeover ||
        client.isApplyingRemoteState ||
        active == null ||
        snapshot == null) {
      playback.setConnectRemoteMirror(null);
      return;
    }
    playback.setConnectRemoteMirror(
      AriamiRemotePlayback(
        snapshot: snapshot,
        deviceId: active.id,
        deviceName: active.name,
        deviceType: active.type,
        receivedAt: client.remoteSnapshotAt,
      ),
      sendCommand: client.sendCommand,
    );
  }

  void transferTo(String deviceId) => _client?.transferTo(deviceId);
  void sendCommand(String command, [Map<String, dynamic>? arguments]) =>
      _client?.sendCommand(command, arguments);

  /// How often a mirroring device checks that remote state is still arriving,
  /// and how long a silence has to last before the socket counts as dead. The
  /// active device republishes on every change and at least once per ping
  /// (20s), so a playing remote that has gone quiet this long is unreachable.
  static const _staleCheckInterval = Duration(seconds: 15);
  static const _staleStateTimeout = Duration(seconds: 50);

  /// Repairs a socket the OS suspended without closing it. Android can freeze a
  /// backgrounded process's connection with no close event, leaving the client
  /// "connected" while every state push is lost — the mirrored notification
  /// would then sit frozen on whatever arrived last.
  void _repairStaleSocket() {
    final client = _client;
    if (client == null || !client.isConnected || client.isThisDeviceActive) {
      return;
    }
    // Only a playing remote guarantees a steady stream of updates to miss.
    if (!(client.remoteSnapshot?.isPlaying ?? false)) return;
    final receivedAt = client.remoteSnapshotAt;
    if (receivedAt == null ||
        DateTime.now().difference(receivedAt) < _staleStateTimeout) {
      return;
    }
    unawaited(client.refreshState());
  }

  /// Reloads the authoritative Connect session after a foreground resume or
  /// manual refresh. This also repairs sockets left half-open while the mobile
  /// process was suspended in the background.
  Future<void> refresh() async {
    await _connectToCurrentEndpoint();
    final client = _client;
    if (client != null && !_ownsAudibleSession(client)) {
      await client.refreshState();
    }
    notifyListeners();
  }

  /// Whether this phone is the audible owner of the Connect session.
  ///
  /// [AriamiConnectClient.refreshState] repairs a suspended socket by closing
  /// and reopening it, which the hub cannot tell apart from the owner dying:
  /// it fails the playing session over immediately and then pauses this device
  /// as the former owner the moment it reconnects. An owner that is still
  /// audible therefore leaves its socket alone and lets the ping/liveness
  /// timers reconnect if the socket really is dead.
  bool _ownsAudibleSession(AriamiConnectClient client) =>
      client.isConnected &&
      client.isThisDeviceActive &&
      (_playback?.localIsPlaying ?? false);

  /// Silences this phone and leaves Connect without publishing a final paused
  /// snapshot, allowing the hub to continue a playing session elsewhere.
  Future<void> leave() => stop(stopLocalPlayback: true);

  Future<void> stop({bool stopLocalPlayback = false}) async {
    _generation++;
    _staleStateTimer?.cancel();
    _staleStateTimer = null;
    final playback = _playback;
    final localWasPlaying = playback != null &&
        !playback.isConnectRemoteActive &&
        playback.localIsPlaying;
    playback?.removeListener(_onPlaybackChanged);
    playback?.setConnectRemoteMirror(null);
    _playback = null;
    final serverSubscription = _serverSubscription;
    _serverSubscription = null;
    final client = _client;
    _client = null;
    _connectedBaseUrl = null;
    _started = false;
    _pendingLocalTakeover = false;
    final serverStop = serverSubscription?.cancel();
    Future<void>? clientStop;
    if (stopLocalPlayback && localWasPlaying) {
      clientStop = client == null
          ? playback.pauseLocal()
          : client.relinquishPlayback(playback.pauseLocal);
    } else {
      clientStop = client?.dispose();
    }
    await Future.wait(<Future<void>>[
      if (serverStop != null) serverStop,
      if (clientStop != null) clientStop,
    ]);
    notifyListeners();
  }
}
