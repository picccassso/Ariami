import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:ariami_core/models/connect_models.dart';
import 'package:ariami_core/models/websocket_models.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef ConnectCommandHandler = Future<void> Function(
  String command,
  Map<String, dynamic> arguments,
);

/// Resilient client transport for Ariami Connect.
///
/// It uses a dedicated WebSocket so library-sync reconnects and playback
/// presence cannot accidentally tear each other down.
class AriamiConnectClient {
  AriamiConnectClient({
    required this.deviceId,
    required this.deviceName,
    required this.clientType,
    required this.snapshotProvider,
    required this.applySnapshot,
    required this.handleCommand,
    required this.pauseForTransfer,
    this.onChanged,
    this.onServerNotification,
  });

  /// Optional diagnostics sink (e.g. debugPrint). Connect state flows across
  /// three devices and a hub; when a session desyncs in the field, these
  /// breadcrumbs are the only way to see which hop dropped it.
  static void Function(String message)? logger;

  final String deviceId;
  final String deviceName;
  final String clientType;
  final AriamiPlaybackSnapshot Function() snapshotProvider;
  final Future<void> Function(AriamiPlaybackSnapshot snapshot) applySnapshot;
  final ConnectCommandHandler handleCommand;
  final Future<void> Function() pauseForTransfer;
  final void Function()? onChanged;

  /// Receives account-scoped server pushes that arrive on the Connect socket
  /// but are not part of the Connect protocol itself (e.g.
  /// `listening_stats_updated` fired when another device uploads stats).
  final void Function(WsMessage message)? onServerNotification;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  Timer? _welcomeTimer;
  String? _baseUrl;
  String? _sessionToken;
  int _reconnectAttempt = 0;
  bool _closedByUser = false;
  bool _connecting = false;
  int _lastRevision = -1;

  bool isConnected = false;
  bool isApplyingRemoteState = false;
  String? activeDeviceId;
  AriamiPlaybackSnapshot? remoteSnapshot;

  /// Local receipt time of [remoteSnapshot], used to extrapolate the remote
  /// position without depending on the other device's clock.
  DateTime? remoteSnapshotAt;
  String? errorMessage;
  List<AriamiConnectDevice> devices = const <AriamiConnectDevice>[];

  void _log(String message) => logger?.call('[$deviceId] $message');

  bool get isThisDeviceActive => activeDeviceId == deviceId;
  AriamiConnectDevice? get activeDevice {
    for (final device in devices) {
      if (device.id == activeDeviceId) return device;
    }
    return null;
  }

  /// This device's entry in the server's device list, which carries the
  /// server-side display name (including any user rename).
  AriamiConnectDevice? get thisDevice {
    for (final device in devices) {
      if (device.id == deviceId) return device;
    }
    return null;
  }

  Future<void> connect({required String baseUrl, String? sessionToken}) async {
    _baseUrl = baseUrl;
    _sessionToken = sessionToken;
    _closedByUser = false;
    await _open();
  }

  Future<void> _open() async {
    if (_connecting || isConnected || _closedByUser || _baseUrl == null) return;
    _connecting = true;
    _reconnectTimer?.cancel();
    try {
      final httpUri = Uri.parse(_baseUrl!);
      final wsUri = httpUri.replace(
        scheme: httpUri.scheme == 'https' ? 'wss' : 'ws',
        path: '${httpUri.path.replaceAll(RegExp(r'/+$'), '')}/api/ws',
        query: null,
        fragment: null,
      );
      final channel = WebSocketChannel.connect(wsUri);
      _channel = channel;
      _subscription = channel.stream.listen(
        _handleRawMessage,
        onError: (_) => _handleDisconnect(),
        onDone: _handleDisconnect,
        cancelOnError: false,
      );
      await channel.ready.timeout(const Duration(seconds: 8));
      if (_channel != channel || _closedByUser) return;
      isConnected = true;
      errorMessage = null;
      _reconnectAttempt = 0;
      _send(WsMessage(
        type: WsMessageType.identify,
        data: <String, dynamic>{
          'deviceId': deviceId,
          'deviceName': deviceName,
          if (_sessionToken != null && _sessionToken!.isNotEmpty)
            'sessionToken': _sessionToken,
          'clientType': clientType,
        },
      ));
      _welcomeTimer?.cancel();
      _welcomeTimer = Timer(const Duration(seconds: 5), () {
        if (devices.isEmpty && activeDeviceId == null) {
          errorMessage = 'This Ariami server does not support Connect yet.';
          onChanged?.call();
        }
      });
      _send(WsMessage(
        type: AriamiConnectMessageType.hello,
        data: const <String, dynamic>{
          'protocolVersion': 1,
          'canPlay': true,
        },
      ));
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        _send(PingMessage());
        if (isThisDeviceActive) publishState();
      });
      onChanged?.call();
    } catch (_) {
      errorMessage = 'Ariami Connect is reconnecting…';
      _handleDisconnect();
    } finally {
      _connecting = false;
    }
  }

  void _handleRawMessage(dynamic raw) {
    try {
      final message = WsMessage.fromJson(
        jsonDecode(raw as String) as Map<String, dynamic>,
      );
      final data = message.data ?? const <String, dynamic>{};
      switch (message.type) {
        case AriamiConnectMessageType.welcome:
          _welcomeTimer?.cancel();
          errorMessage = null;
          _readDevices(data);
          _readState(data);
          // The first device with local playback seeds a new hub session.
          if (activeDeviceId == null && snapshotProvider().queue.isNotEmpty) {
            publishState(activate: true);
          }
        case AriamiConnectMessageType.devices:
          _readDevices(data);
        case AriamiConnectMessageType.state:
          _readState(data);
        case AriamiConnectMessageType.command:
          unawaited(_runCommand(data));
        case AriamiConnectMessageType.commandResult:
          if (data['ok'] == false) {
            errorMessage = data['message'] as String? ??
                'The playback device could not run that command.';
            onChanged?.call();
          }
        case AriamiConnectMessageType.transfer:
          unawaited(_runTransfer(data));
        case AriamiConnectMessageType.error:
          errorMessage = data['message'] as String? ?? 'Ariami Connect error';
          onChanged?.call();
        case WsMessageType.listeningStatsUpdated:
        case WsMessageType.pinsChanged:
        case WsMessageType.playlistEditsChanged:
          onServerNotification?.call(message);
      }
    } catch (_) {
      // Ignore malformed messages; the authenticated socket remains usable.
    }
  }

  void _readDevices(Map<String, dynamic> data) {
    final rawDevices = data['devices'] as List<dynamic>?;
    if (rawDevices != null) {
      devices = rawDevices
          .whereType<Map>()
          .map((item) => AriamiConnectDevice.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .where((device) => device.id.isNotEmpty)
          .toList(growable: false);
    }
    activeDeviceId = data['activeDeviceId'] as String?;
    onChanged?.call();
  }

  void _readState(Map<String, dynamic> data) {
    final revision = (data['revision'] as num?)?.toInt() ?? 0;
    if (revision < _lastRevision) {
      _log('state rejected: revision $revision < $_lastRevision');
      return;
    }
    _lastRevision = revision;
    activeDeviceId = data['activeDeviceId'] as String? ?? activeDeviceId;
    final raw = data['snapshot'];
    if (raw is Map) {
      remoteSnapshot = AriamiPlaybackSnapshot.fromJson(
        Map<String, dynamic>.from(raw),
      );
      remoteSnapshotAt = DateTime.now();
    }
    _log('state applied: revision $revision, active $activeDeviceId, '
        'track ${remoteSnapshot?.currentTrackId}, '
        'playing ${remoteSnapshot?.isPlaying}');
    onChanged?.call();
  }

  Future<void> _runCommand(Map<String, dynamic> data) async {
    final commandId = data['commandId'] as String? ?? '';
    _log('command in: ${data['command']} from ${data['requestedBy']}');
    try {
      await handleCommand(
        data['command'] as String? ?? '',
        data['arguments'] is Map
            ? Map<String, dynamic>.from(data['arguments'] as Map)
            : const <String, dynamic>{},
      );
      publishState();
      _sendResult(commandId, ok: true);
    } catch (error) {
      _sendResult(commandId, ok: false, message: '$error');
    }
  }

  Future<void> _runTransfer(Map<String, dynamic> data) async {
    final phase = data['phase'] as String? ?? 'commit';
    final transferId = data['transferId'] as String? ?? '';
    final sourceId = data['sourceDeviceId'] as String?;
    final targetId = data['targetDeviceId'] as String?;
    _log('transfer $phase: $sourceId -> $targetId');
    if (phase == 'prepare' && targetId == deviceId) {
      final raw = data['snapshot'];
      if (raw is! Map) return;
      isApplyingRemoteState = true;
      onChanged?.call();
      try {
        final snapshot = AriamiPlaybackSnapshot.fromJson(
          Map<String, dynamic>.from(raw),
        ).compensated(DateTime.now().toUtc());
        // Load and seek without starting. The source keeps playing until the
        // target confirms readiness, preventing a failed load from silencing
        // the session.
        await applySnapshot(snapshot.copyWith(isPlaying: false));
        remoteSnapshot = snapshot;
        remoteSnapshotAt = DateTime.now();
        _send(WsMessage(
          type: AriamiConnectMessageType.transferResult,
          data: <String, dynamic>{'transferId': transferId, 'ok': true},
        ));
      } catch (error) {
        _send(WsMessage(
          type: AriamiConnectMessageType.transferResult,
          data: <String, dynamic>{
            'transferId': transferId,
            'ok': false,
            'message': '$error',
          },
        ));
      } finally {
        isApplyingRemoteState = false;
        onChanged?.call();
      }
      return;
    }

    if (phase != 'commit') return;
    activeDeviceId = targetId;
    // The commit carries the session's authoritative snapshot and revision;
    // adopt them on every device so remote mirrors reflect the handoff
    // immediately instead of waiting for the new active device to publish.
    final raw = data['snapshot'];
    final snapshot = raw is Map
        ? AriamiPlaybackSnapshot.fromJson(
            Map<String, dynamic>.from(raw),
          ).compensated(DateTime.now().toUtc())
        : null;
    if (snapshot != null) {
      remoteSnapshot = snapshot;
      remoteSnapshotAt = DateTime.now();
    }
    final revision = (data['revision'] as num?)?.toInt();
    if (revision != null && revision > _lastRevision) {
      _lastRevision = revision;
    }
    if (targetId == deviceId) {
      if (snapshot == null) return;
      isApplyingRemoteState = true;
      try {
        await handleCommand(AriamiConnectCommand.seek,
            <String, dynamic>{'positionMs': snapshot.positionMs});
        if (snapshot.isPlaying) {
          // Playback APIs such as just_audio return a play() future that does
          // not complete until the track ends, pauses, or stops. Starting the
          // target must not keep the whole transfer in "applying" state for
          // that long, because state publications are suppressed while this
          // flag is set.
          unawaited(
            handleCommand(
              AriamiConnectCommand.play,
              const <String, dynamic>{},
            ).catchError((Object error, StackTrace stackTrace) {
              _log('transfer playback start failed: $error');
              errorMessage = 'The playback device could not start playback.';
              onChanged?.call();
            }),
          );
        } else {
          await handleCommand(
            AriamiConnectCommand.pause,
            const <String, dynamic>{},
          );
        }
      } finally {
        isApplyingRemoteState = false;
      }
      publishState();
    } else if (sourceId == deviceId) {
      await pauseForTransfer();
    }
    onChanged?.call();
  }

  void publishState({bool activate = false}) {
    if (!isConnected || isApplyingRemoteState) return;
    final snapshot = snapshotProvider();
    _log('publish: activate $activate, track ${snapshot.currentTrackId}, '
        'playing ${snapshot.isPlaying}, thinksActive $isThisDeviceActive');
    _send(WsMessage(
      type: AriamiConnectMessageType.state,
      data: <String, dynamic>{
        'activate': activate,
        'snapshot': snapshot.toJson(),
      },
    ));
  }

  void sendCommand(String command, [Map<String, dynamic>? arguments]) {
    if (!AriamiConnectCommand.supported.contains(command)) return;
    _send(WsMessage(
      type: AriamiConnectMessageType.command,
      data: <String, dynamic>{
        'commandId': '$deviceId-${DateTime.now().microsecondsSinceEpoch}',
        'command': command,
        'arguments': arguments ?? const <String, dynamic>{},
      },
    ));
  }

  /// Asks the server to rename this device. The server persists the name and
  /// answers with a devices broadcast, so the UI updates via [onChanged].
  void renameThisDevice(String name) {
    final normalized = normalizeDeviceDisplayName(name);
    if (normalized == null || !isConnected) return;
    _send(WsMessage(
      type: AriamiConnectMessageType.rename,
      data: <String, dynamic>{'name': normalized},
    ));
  }

  void transferTo(String targetDeviceId) {
    if (targetDeviceId.isEmpty || targetDeviceId == activeDeviceId) return;
    errorMessage = null;
    _send(WsMessage(
      type: AriamiConnectMessageType.transfer,
      data: <String, dynamic>{'targetDeviceId': targetDeviceId},
    ));
  }

  void _sendResult(String commandId, {required bool ok, String? message}) {
    _send(WsMessage(
      type: AriamiConnectMessageType.commandResult,
      data: <String, dynamic>{
        'commandId': commandId,
        'ok': ok,
        if (message != null) 'message': message,
      },
    ));
  }

  void _send(WsMessage message) {
    if (_channel == null) return;
    try {
      _channel!.sink.add(jsonEncode(message.toJson()));
    } catch (_) {
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    final wasConnected = isConnected;
    isConnected = false;
    _pingTimer?.cancel();
    _welcomeTimer?.cancel();
    _pingTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    // Revisions live in the server's memory; after a drop the next welcome
    // (possibly from a restarted hub counting from zero again) is the
    // authoritative baseline. Keeping the old high-water mark here silently
    // discarded every state update after a server restart, freezing remote
    // mirrors while commands kept working.
    _lastRevision = -1;
    if (wasConnected) _log('disconnected');
    if (wasConnected) onChanged?.call();
    if (_closedByUser) return;
    _reconnectTimer?.cancel();
    final seconds = min(30, 1 << min(_reconnectAttempt++, 5));
    _reconnectTimer = Timer(Duration(seconds: seconds), _open);
  }

  Future<void> dispose() async {
    _closedByUser = true;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _welcomeTimer?.cancel();
    await _subscription?.cancel();
    await _channel?.sink.close(1000, 'Client closed');
    _channel = null;
    isConnected = false;
  }
}
