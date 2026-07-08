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
  Timer? _publishTimer;
  String? _lastTrackId;
  bool _lastPlaying = false;
  String? _connectedBaseUrl;
  bool _started = false;
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
    if (!_started) {
      _started = true;
      _generation++;
      playback.addListener(_onPlaybackChanged);
      _serverSubscription = _connection.serverInfoStream.listen((_) {
        unawaited(_connectToCurrentEndpoint());
      });
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
      AriamiConnectClient.logger = (message) => debugPrint('[Connect] $message');
    }
    final client = AriamiConnectClient(
      deviceId: deviceId,
      deviceName: deviceName,
      clientType: 'mobile',
      snapshotProvider: () => playback.connectSnapshot,
      applySnapshot: playback.applyConnectSnapshot,
      handleCommand: _handleCommand,
      pauseForTransfer: playback.pauseLocal,
      onChanged: _onClientChanged,
      // Stats pushes for this account arrive on the Connect socket; refresh
      // the account-wide view when another device uploads listening activity.
      onServerNotification: (_) =>
          unawaited(AccountStatsService().refreshSummary()),
    );
    _client = client;
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
    if (playback == null || client == null || client.isApplyingRemoteState) {
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
        (playing && !_lastPlaying && !client.isThisDeviceActive);
    _lastTrackId = trackId;
    _lastPlaying = playing;
    if (activate) {
      // Publish takeovers immediately so the hub pauses the old device and
      // confirms this one as active before stale remote state can flash back.
      _publishTimer?.cancel();
      client.publishState(activate: true);
      return;
    }
    if (_publishTimer?.isActive ?? false) return;
    _publishTimer = Timer(const Duration(milliseconds: 500), () {
      client.publishState();
    });
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

  Future<void> stop() async {
    _generation++;
    _publishTimer?.cancel();
    _playback?.removeListener(_onPlaybackChanged);
    _playback?.setConnectRemoteMirror(null);
    _playback = null;
    await _serverSubscription?.cancel();
    _serverSubscription = null;
    final client = _client;
    _client = null;
    await client?.dispose();
    _connectedBaseUrl = null;
    _started = false;
    notifyListeners();
  }
}
