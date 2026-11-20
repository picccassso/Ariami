import 'dart:async';

import 'package:ariami_core/models/connect_models.dart';
import 'package:ariami_core/models/websocket_models.dart';
import 'package:ariami_core/services/connect/connect_client.dart';
import 'package:ariami_core/services/connect/remote_playback.dart';
import 'package:flutter/foundation.dart';

import 'audio_controller.dart';
import 'connection_controller.dart';

class AriamiConnectController extends ChangeNotifier {
  AriamiConnectClient? _client;
  AudioController? _audio;

  /// Invoked when the server pushes `listening_stats_updated` — another of
  /// this account's devices uploaded listening activity.
  void Function()? onListeningStatsUpdated;
  void Function()? onPinsChanged;

  /// Invoked when another of this account's devices hid or unhid something.
  void Function()? onHiddenChanged;
  /// Invoked when another of this account's devices changed library curation.
  void Function()? onCurationChanged;
  void Function()? onPlaylistEditsChanged;
  void Function()? onArtistImagesChanged;

  /// Invoked when the server pushes `sync_token_advanced` — the catalog
  /// changed and incremental library sync can catch up to [latestToken].
  void Function(int latestToken)? onSyncTokenAdvanced;
  String? _lastTrackId;
  bool _lastPlaying = false;
  bool _pendingLocalTakeover = false;
  bool _disposed = false;
  int _attachGeneration = 0;

  List<AriamiConnectDevice> get devices =>
      _client?.devices ?? const <AriamiConnectDevice>[];
  String? get activeDeviceId => _client?.activeDeviceId;
  AriamiConnectDevice? get activeDevice => _client?.activeDevice;
  AriamiConnectDevice? get thisDevice => _client?.thisDevice;
  bool get isConnected => _client?.isConnected ?? false;
  bool get isThisDeviceActive => _client?.isThisDeviceActive ?? false;
  String? get errorMessage => _client?.errorMessage;

  Future<void> attach(
    ConnectionController connection,
    AudioController audio, {
    String clientType = 'web',
    Set<String> supportedFeatures = const <String>{},
  }) async {
    final generation = ++_attachGeneration;
    await detach(invalidateAttach: false);
    if (_disposed || generation != _attachGeneration) return;
    final baseUrl = connection.connectBaseUrl;
    if (baseUrl == null) return;
    _audio = audio;
    _lastTrackId = audio.localCurrentTrack?.id;
    _lastPlaying = audio.localIsPlaying;
    _pendingLocalTakeover = _lastPlaying && audio.localCurrentTrack != null;
    // Listen before resolving the persisted device id: the user can press
    // play while that asynchronous startup work is still in flight.
    audio.addTickingListener(_onAudioChanged);
    final deviceId = await connection.connectDeviceId;
    if (_disposed || generation != _attachGeneration) return;
    if (kDebugMode) {
      AriamiConnectClient.logger =
          (message) => debugPrint('[Connect] $message');
    }
    final client = AriamiConnectClient(
      deviceId: deviceId,
      deviceName: connection.connectDeviceName,
      clientType: clientType,
      snapshotProvider: () => audio.connectSnapshot,
      applySnapshot: audio.applyConnectSnapshot,
      handleCommand: _handleCommand,
      pauseForTransfer: audio.pauseLocal,
      supportedCommands: AudioController.connectSupportedCommands,
      supportedFeatures: supportedFeatures,
      onChanged: _notifyChanged,
      onAuthenticationRequired: connection.requireSignIn,
      onServerNotification: (message) {
        if (message.type == WsMessageType.listeningStatsUpdated) {
          onListeningStatsUpdated?.call();
        } else if (message.type == WsMessageType.pinsChanged) {
          onPinsChanged?.call();
        } else if (message.type == WsMessageType.hiddenChanged) {
          onHiddenChanged?.call();
        } else if (message.type == WsMessageType.curationChanged) {
          onCurationChanged?.call();
        } else if (message.type == WsMessageType.playlistEditsChanged) {
          onPlaylistEditsChanged?.call();
        } else if (message.type == WsMessageType.artistImagesChanged) {
          onArtistImagesChanged?.call();
        } else if (message.type == WsMessageType.syncTokenAdvanced) {
          onSyncTokenAdvanced?.call(
            SyncTokenAdvancedMessage.fromWsMessage(message).latestToken,
          );
        }
      },
    );
    _client = client;
    if (_pendingLocalTakeover) {
      _pendingLocalTakeover = false;
      client.requestLocalTakeover();
    }
    await client.connect(
      baseUrl: baseUrl,
      sessionToken: connection.connectSessionToken,
    );
    if (_disposed || generation != _attachGeneration) {
      await client.dispose();
      return;
    }
    _notifyChanged();
  }

  void _onAudioChanged() {
    final audio = _audio;
    final client = _client;
    if (audio == null || (client?.isApplyingRemoteState ?? false)) return;
    // While mirroring another device there is no local playback worth
    // publishing; the mirror's own notifications must not look like takeovers.
    if (audio.isRemoteActive) return;
    final trackId = audio.localCurrentTrack?.id;
    final playing = audio.localIsPlaying;
    // Starting music locally is a takeover; a mere track change while paused
    // (e.g. queueing into an empty queue) is not.
    final activate = audio.isLocalPlaybackAllowed &&
        ((playing && trackId != null && trackId != _lastTrackId) ||
            (playing &&
                !_lastPlaying &&
                !(client?.isThisDeviceActive ?? false)));
    _lastTrackId = trackId;
    _lastPlaying = playing;
    if (!playing || trackId == null || !audio.isLocalPlaybackAllowed) {
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
    String command,
    Map<String, dynamic> arguments,
  ) async {
    await _audio?.handleConnectCommand(command, arguments);
  }

  void transferTo(String deviceId) => _client?.transferTo(deviceId);
  void sendCommand(String command, [Map<String, dynamic>? arguments]) =>
      _client?.sendCommand(command, arguments);

  /// Renames this computer across the account: the server persists the name
  /// and pushes the updated device list to every Ariami Connect client.
  void renameThisDevice(String name) => _client?.renameThisDevice(name);

  void _notifyChanged() {
    _syncRemoteMirror();
    if (!_disposed) notifyListeners();
  }

  /// Feeds the audio controller a mirror of the active device's playback
  /// whenever another device owns the session, and clears it otherwise.
  void _syncRemoteMirror() {
    final audio = _audio;
    if (audio == null) return;
    final client = _client;
    if (client != null &&
        !client.isSessionReady &&
        !client.hasPendingLocalTakeover &&
        !client.isApplyingRemoteState) {
      return;
    }
    final active = client?.activeDevice;
    final snapshot = client?.remoteSnapshot;
    if (client == null ||
        !client.isConnected ||
        client.isThisDeviceActive ||
        client.hasPendingLocalTakeover ||
        client.isApplyingRemoteState ||
        active == null ||
        snapshot == null) {
      audio.setRemoteMirror(null);
      return;
    }
    audio.setRemoteMirror(
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

  Future<void> detach({bool invalidateAttach = true}) async {
    if (invalidateAttach) _attachGeneration++;
    _audio?.removeTickingListener(_onAudioChanged);
    _audio?.setRemoteMirror(null);
    _audio = null;
    final client = _client;
    _client = null;
    await client?.dispose();
    _pendingLocalTakeover = false;
    _notifyChanged();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(detach());
    super.dispose();
  }
}
