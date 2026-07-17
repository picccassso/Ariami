import 'dart:async';
import 'dart:collection';
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
    this.commandAckTimeout = const Duration(seconds: 4),
    this.maxCommandAttempts = 4,
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
  final Duration commandAckTimeout;
  final int maxCommandAttempts;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  Timer? _welcomeTimer;
  Future<void>? _refreshFuture;
  String? _baseUrl;
  String? _sessionToken;
  int _reconnectAttempt = 0;
  bool _closedByUser = false;
  bool _connecting = false;
  bool _isWelcomed = false;
  bool _takeoverRequested = false;
  bool _takeoverSentOnCurrentConnection = false;
  int _hubProtocolVersion = 1;
  int _lastRevision = -1;
  final LinkedHashMap<String, _PendingOutboundCommand> _pendingCommands =
      LinkedHashMap<String, _PendingOutboundCommand>();
  final LinkedHashMap<String, Map<String, dynamic>> _handledCommandResults =
      LinkedHashMap<String, Map<String, dynamic>>();

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
  bool get hasPendingLocalTakeover => _takeoverRequested;
  int get pendingCommandCount => _pendingCommands.length;
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
    WebSocketChannel? openingChannel;
    try {
      final httpUri = Uri.parse(_baseUrl!);
      final wsUri = httpUri.replace(
        scheme: httpUri.scheme == 'https' ? 'wss' : 'ws',
        path: '${httpUri.path.replaceAll(RegExp(r'/+$'), '')}/api/ws',
        query: null,
        fragment: null,
      );
      final channel = WebSocketChannel.connect(wsUri);
      openingChannel = channel;
      _channel = channel;
      _subscription = channel.stream.listen(
        _handleRawMessage,
        onError: (_) => _handleDisconnect(channel),
        onDone: () => _handleDisconnect(channel),
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
      _handleDisconnect(openingChannel);
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
          _isWelcomed = true;
          _hubProtocolVersion = (data['protocolVersion'] as num?)?.toInt() ?? 1;
          errorMessage = null;
          _readDevices(data);
          _readState(data);
          // A local play intent can happen while this socket is still opening.
          // It must win over the stale remote snapshot carried by welcome,
          // otherwise local audio keeps playing underneath a remote UI mirror.
          if (_takeoverRequested) {
            _flushTakeoverRequest();
          } else if (activeDeviceId == null &&
              snapshotProvider().queue.isNotEmpty) {
            // The first device with local playback seeds a new hub session.
            publishState(activate: true);
          }
          _flushPendingCommands();
        case AriamiConnectMessageType.devices:
          _readDevices(data);
        case AriamiConnectMessageType.state:
          _readState(data);
        case AriamiConnectMessageType.command:
          unawaited(_runCommand(data));
        case AriamiConnectMessageType.commandResult:
          final commandId = data['commandId'] as String?;
          final pending =
              commandId == null ? null : _pendingCommands.remove(commandId);
          pending?.retryTimer?.cancel();
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
        case WsMessageType.syncTokenAdvanced:
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
    _reconcileTakeoverRequest();
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
    _reconcileTakeoverRequest();
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
    final previousResult = _handledCommandResults[commandId];
    if (commandId.isNotEmpty && previousResult != null) {
      _send(WsMessage(
        type: AriamiConnectMessageType.commandResult,
        data: previousResult,
      ));
      return;
    }
    try {
      await handleCommand(
        data['command'] as String? ?? '',
        data['arguments'] is Map
            ? Map<String, dynamic>.from(data['arguments'] as Map)
            : const <String, dynamic>{},
      );
      publishState();
      _sendResult(commandId, ok: true, remember: true);
    } catch (error) {
      _sendResult(commandId, ok: false, message: '$error', remember: true);
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
    if (activate) {
      requestLocalTakeover();
      return;
    }
    _publishState(activate: false);
  }

  /// Remembers a user-initiated local play until the hub confirms that this
  /// device owns the session.
  ///
  /// Playback can start before the Connect socket receives its welcome. A
  /// durable request prevents that welcome's older remote snapshot from
  /// replacing the local UI while both devices continue making sound.
  void requestLocalTakeover() {
    _takeoverRequested = true;
    _flushTakeoverRequest();
  }

  void _flushTakeoverRequest() {
    if (!_takeoverRequested ||
        _takeoverSentOnCurrentConnection ||
        !isConnected ||
        !_isWelcomed ||
        isApplyingRemoteState) {
      return;
    }
    _takeoverSentOnCurrentConnection = true;
    _publishState(activate: true);
  }

  void _reconcileTakeoverRequest() {
    // A welcome can say this device was already active before the queued
    // request has published its newer local track. Only the hub response to a
    // request sent on this connection confirms both ownership and snapshot.
    if (_takeoverRequested &&
        _takeoverSentOnCurrentConnection &&
        activeDeviceId == deviceId) {
      _takeoverRequested = false;
      _takeoverSentOnCurrentConnection = false;
    }
  }

  void _publishState({required bool activate}) {
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
    final commandId = '$deviceId-${DateTime.now().microsecondsSinceEpoch}';
    final pending = _PendingOutboundCommand(
      message: WsMessage(
        type: AriamiConnectMessageType.command,
        data: <String, dynamic>{
          'commandId': commandId,
          'command': command,
          'arguments': arguments ?? const <String, dynamic>{},
        },
      ),
    );
    _pendingCommands[commandId] = pending;
    while (_pendingCommands.length > 64) {
      final oldest = _pendingCommands.remove(_pendingCommands.keys.first);
      oldest?.retryTimer?.cancel();
    }
    _dispatchCommand(commandId, pending);
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

  /// Reopens the dedicated socket so the next welcome rehydrates the
  /// authoritative device list and playback snapshot.
  ///
  /// Mobile operating systems can suspend a backgrounded app without first
  /// delivering a WebSocket close event. In that case [isConnected] remains
  /// true even though state pushes are no longer arriving. A deliberate
  /// reconnect is therefore more reliable than sending a refresh message on
  /// the possibly stale socket.
  Future<void> refreshState() {
    final inFlight = _refreshFuture;
    if (inFlight != null) return inFlight;
    final refresh = _refreshState();
    _refreshFuture = refresh;
    return refresh.whenComplete(() {
      if (identical(_refreshFuture, refresh)) {
        _refreshFuture = null;
      }
    });
  }

  Future<void> _refreshState() async {
    if (_closedByUser || _baseUrl == null) return;
    if (_connecting) return;
    if (!isConnected) {
      await _open();
      return;
    }

    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _welcomeTimer?.cancel();
    _pingTimer = null;
    _welcomeTimer = null;
    _isWelcomed = false;
    _lastRevision = -1;
    _takeoverSentOnCurrentConnection = false;
    isConnected = false;

    final subscription = _subscription;
    final channel = _channel;
    _subscription = null;
    _channel = null;
    await subscription?.cancel();
    try {
      await channel?.sink
          .close(1000, 'Refreshing Connect state')
          .timeout(const Duration(seconds: 1));
    } catch (_) {
      // A stale mobile socket may not acknowledge close. Opening its
      // replacement is still safe because the server replaces duplicate
      // connections for the same device id.
    }
    await _open();
  }

  void _sendResult(
    String commandId, {
    required bool ok,
    String? message,
    bool remember = false,
  }) {
    final data = <String, dynamic>{
      'commandId': commandId,
      'ok': ok,
      if (message != null) 'message': message,
    };
    if (remember && commandId.isNotEmpty) {
      _handledCommandResults.remove(commandId);
      _handledCommandResults[commandId] = data;
      while (_handledCommandResults.length > 256) {
        _handledCommandResults.remove(_handledCommandResults.keys.first);
      }
    }
    _send(WsMessage(
      type: AriamiConnectMessageType.commandResult,
      data: data,
    ));
  }

  /// Since welcome protocol version 2 the hub deduplicates replayed
  /// commandIds, making retransmission safe. Version 1 hubs forward every
  /// replay to the active device, which would run a non-idempotent command
  /// (next, toggle, cycle_repeat) twice — so never retry against them.
  bool get _hubDeduplicatesCommands => _hubProtocolVersion >= 2;

  void _flushPendingCommands() {
    if (!isConnected || !_isWelcomed) return;
    for (final entry in _pendingCommands.entries.toList(growable: false)) {
      if (entry.value.attempts > 0 && !_hubDeduplicatesCommands) {
        // Already sent once to a hub that cannot dedupe a replay; drop it
        // rather than risk double execution on the playback device.
        _pendingCommands.remove(entry.key);
        continue;
      }
      _dispatchCommand(entry.key, entry.value);
    }
  }

  void _dispatchCommand(String commandId, _PendingOutboundCommand pending) {
    if (!isConnected ||
        !_isWelcomed ||
        _pendingCommands[commandId] != pending) {
      return;
    }
    pending.retryTimer?.cancel();
    pending.attempts += 1;
    _send(pending.message);
    pending.retryTimer = Timer(commandAckTimeout, () {
      if (_pendingCommands[commandId] != pending) return;
      if (!isConnected || !_isWelcomed) return;
      if (pending.attempts < maxCommandAttempts && _hubDeduplicatesCommands) {
        _dispatchCommand(commandId, pending);
        return;
      }
      _pendingCommands.remove(commandId);
      _log('Command $commandId was not acknowledged after '
          '${pending.attempts} attempts');
    });
  }

  void _send(WsMessage message) {
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(jsonEncode(message.toJson()));
    } catch (_) {
      _handleDisconnect(channel);
    }
  }

  void _handleDisconnect([WebSocketChannel? source]) {
    // Ignore completion/error callbacks from a socket that has already been
    // superseded by an explicit refresh or a newer reconnect.
    if (source != null && !identical(_channel, source)) return;
    final wasConnected = isConnected;
    isConnected = false;
    _isWelcomed = false;
    _pingTimer?.cancel();
    _welcomeTimer?.cancel();
    _pingTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    for (final pending in _pendingCommands.values) {
      pending.retryTimer?.cancel();
      pending.retryTimer = null;
    }
    // Revisions live in the server's memory; after a drop the next welcome
    // (possibly from a restarted hub counting from zero again) is the
    // authoritative baseline. Keeping the old high-water mark here silently
    // discarded every state update after a server restart, freezing remote
    // mirrors while commands kept working.
    _lastRevision = -1;
    // A takeover sent just before the drop may never have been acknowledged.
    // Keep the intent, but allow the replacement socket to publish it again.
    _takeoverSentOnCurrentConnection = false;
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
    for (final pending in _pendingCommands.values) {
      pending.retryTimer?.cancel();
    }
    _pendingCommands.clear();
    _takeoverRequested = false;
    _takeoverSentOnCurrentConnection = false;
    await _subscription?.cancel();
    await _channel?.sink.close(1000, 'Client closed');
    _channel = null;
    isConnected = false;
  }
}

class _PendingOutboundCommand {
  _PendingOutboundCommand({required this.message});

  final WsMessage message;
  int attempts = 0;
  Timer? retryTimer;
}
