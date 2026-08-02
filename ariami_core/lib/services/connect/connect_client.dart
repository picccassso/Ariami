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

typedef ConnectWebSocketFactory = WebSocketChannel Function(Uri uri);
typedef ConnectTimerFactory = Timer Function(
  Duration duration,
  void Function() callback,
);
typedef ConnectPeriodicTimerFactory = Timer Function(
  Duration duration,
  void Function(Timer timer) callback,
);

WebSocketChannel _connectWebSocket(Uri uri) => WebSocketChannel.connect(uri);
Timer _startTimer(Duration duration, void Function() callback) =>
    Timer(duration, callback);
Timer _startPeriodicTimer(
  Duration duration,
  void Function(Timer timer) callback,
) =>
    Timer.periodic(duration, callback);

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
    this.onAuthenticationRequired,
    this.commandAckTimeout = const Duration(seconds: 4),
    this.maxCommandAttempts = 4,
    this.connectTimeout = const Duration(seconds: 8),
    this.livenessTimeout = const Duration(seconds: 60),
    this.backoffResetAfter = const Duration(seconds: 60),
    this.refreshCloseTimeout = const Duration(seconds: 1),
    this.disposeTimeout = const Duration(seconds: 1),
    this.progressPublishInterval = const Duration(seconds: 1),
    this.webSocketFactory = _connectWebSocket,
    this.timerFactory = _startTimer,
    this.periodicTimerFactory = _startPeriodicTimer,
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
  final void Function()? onAuthenticationRequired;
  final Duration commandAckTimeout;
  final int maxCommandAttempts;
  final Duration connectTimeout;
  final Duration livenessTimeout;
  final Duration backoffResetAfter;
  final Duration refreshCloseTimeout;
  final Duration disposeTimeout;
  final Duration progressPublishInterval;

  /// Transport and timer seams keep fault tests deterministic. Production
  /// callers use the hardened default deadlines above.
  final ConnectWebSocketFactory webSocketFactory;
  final ConnectTimerFactory timerFactory;
  final ConnectPeriodicTimerFactory periodicTimerFactory;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  Timer? _welcomeTimer;
  Timer? _livenessTimer;
  Timer? _backoffResetTimer;
  Timer? _progressPublishTimer;
  Future<void>? _refreshFuture;
  String? _baseUrl;
  String? _sessionToken;
  int _reconnectAttempt = 0;
  bool _closedByUser = false;
  bool _reconnectSuppressed = false;
  bool _connecting = false;
  bool _isWelcomed = false;
  bool _receivedInboundOnCurrentConnection = false;
  bool _takeoverRequested = false;
  bool _takeoverSentOnCurrentConnection = false;
  int _hubProtocolVersion = 1;
  int _lastRevision = -1;
  int _queueCounter = 0;
  int _outboundStateRevision = 0;
  List<Map<String, dynamic>> _remoteQueue = const <Map<String, dynamic>>[];
  List<int> _remoteBackingOrder = const <int>[];
  String? _remoteSourceId;
  String? _lastPublishedQueueFingerprint;
  String? _lastPublishedDiscreteFingerprint;
  String? _awaitingQueueFingerprint;
  DateTime? _lastStatePublishedAt;
  Future<void> _inboundQueue = Future<void>.value();
  Future<void>? _formerOwnerPauseFuture;
  int _lastPausedOwnerEpoch = -1;
  int _connectionGeneration = 0;
  final LinkedHashMap<String, _PendingOutboundCommand> _pendingCommands =
      LinkedHashMap<String, _PendingOutboundCommand>();
  final LinkedHashMap<String, Map<String, dynamic>> _handledCommandResults =
      LinkedHashMap<String, Map<String, dynamic>>();

  bool isConnected = false;
  bool isApplyingRemoteState = false;
  String? activeDeviceId;
  int ownerEpoch = 0;
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
  int get negotiatedProtocolVersion => _hubProtocolVersion;
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
    _reconnectSuppressed = false;
    _reconnectAttempt = 0;
    _hubProtocolVersion = 1;
    _resetSplitState();
    ownerEpoch = 0;
    activeDeviceId = null;
    _lastPausedOwnerEpoch = -1;
    await _open();
  }

  Future<void> _open() async {
    if (_connecting ||
        isConnected ||
        _closedByUser ||
        _reconnectSuppressed ||
        _baseUrl == null) {
      return;
    }
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
      final channel = webSocketFactory(wsUri);
      openingChannel = channel;
      _channel = channel;
      _connectionGeneration++;
      _subscription = channel.stream.listen(
        (raw) => _handleRawMessage(channel, raw),
        onError: (_) => _handleDisconnect(channel),
        onDone: () => _handleDisconnect(channel),
        cancelOnError: false,
      );
      await channel.ready.timeout(connectTimeout);
      if (_channel != channel || _closedByUser) return;
      isConnected = true;
      _receivedInboundOnCurrentConnection = false;
      errorMessage = null;
      _armLivenessWatchdog(channel);
      _backoffResetTimer?.cancel();
      _backoffResetTimer = timerFactory(backoffResetAfter, () {
        if (identical(_channel, channel) &&
            isConnected &&
            _receivedInboundOnCurrentConnection) {
          _reconnectAttempt = 0;
        }
      });
      // Send the capability offer first. New hubs retain it while identify is
      // authenticated asynchronously; old hubs ignore it and proceed normally.
      _send(WsMessage(
        type: AriamiConnectMessageType.hello,
        data: const <String, dynamic>{
          'protocolVersions': AriamiConnectProtocol.supportedVersions,
          'canPlay': true,
        },
      ));
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
      _welcomeTimer = timerFactory(const Duration(seconds: 5), () {
        if (devices.isEmpty && activeDeviceId == null) {
          errorMessage = 'This Ariami server does not support Connect yet.';
          onChanged?.call();
        }
      });
      _pingTimer?.cancel();
      _pingTimer = periodicTimerFactory(const Duration(seconds: 20), (_) {
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

  void _handleRawMessage(WebSocketChannel source, dynamic raw) {
    if (!identical(_channel, source)) return;
    _receivedInboundOnCurrentConnection = true;
    _armLivenessWatchdog(source);
    try {
      final message = WsMessage.fromJson(
        jsonDecode(raw as String) as Map<String, dynamic>,
      );
      final generation = _connectionGeneration;
      _inboundQueue =
          _inboundQueue.then((_) => _handleMessage(message, generation));
    } catch (_) {
      // Ignore malformed messages; the authenticated socket remains usable.
    }
  }

  Future<void> _handleMessage(WsMessage message, int generation) async {
    if (generation != _connectionGeneration) return;
    try {
      final data = message.data ?? const <String, dynamic>{};
      switch (message.type) {
        case AriamiConnectMessageType.welcome:
          _welcomeTimer?.cancel();
          _isWelcomed = true;
          _hubProtocolVersion = (data['protocolVersion'] as num?)?.toInt() ?? 1;
          errorMessage = null;
          if (!await _readDevices(data)) return;
          if (_hubProtocolVersion >= AriamiConnectProtocol.v3) {
            final counter = data['queueCounter'];
            if (counter is num && counter == counter.toInt()) {
              _queueCounter = counter.toInt();
            }
          } else if (!await _readState(data)) {
            return;
          }
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
          await _readDevices(data);
        case AriamiConnectMessageType.queue:
          await _readQueue(data);
        case AriamiConnectMessageType.state:
          await _readState(data);
        case AriamiConnectMessageType.command:
          await _runCommand(data);
        case AriamiConnectMessageType.commandResult:
          final authority = await _acceptAuthority(data);
          if (!authority.accepted) return;
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
          await _runTransfer(data);
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
      // One malformed or failed message must not poison the ordered queue.
    }
  }

  void _armLivenessWatchdog(WebSocketChannel channel) {
    _livenessTimer?.cancel();
    _livenessTimer = timerFactory(livenessTimeout, () {
      if (!identical(_channel, channel) ||
          !isConnected ||
          _closedByUser ||
          _reconnectSuppressed) {
        return;
      }
      _log('No inbound Connect traffic for ${livenessTimeout.inSeconds}s; '
          'replacing the socket');
      unawaited(refreshState());
    });
  }

  Future<bool> _readDevices(Map<String, dynamic> data) async {
    final authority = await _acceptAuthority(data);
    if (!authority.accepted) return false;
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
    _reconcileTakeoverRequest();
    onChanged?.call();
    return true;
  }

  Future<bool> _readState(Map<String, dynamic> data) async {
    final authority = await _acceptAuthority(data);
    if (!authority.accepted) return false;
    final revision = (data[_hubProtocolVersion >= AriamiConnectProtocol.v3
                ? 'stateRevision'
                : 'revision'] as num?)
            ?.toInt() ??
        0;
    if (revision < _lastRevision) {
      _log('state rejected: revision $revision < $_lastRevision');
      return false;
    }
    _reconcileTakeoverRequest();
    if (_hubProtocolVersion >= AriamiConnectProtocol.v3) {
      final rawCounter = data['queueCounter'];
      if (rawCounter is! num ||
          rawCounter != rawCounter.toInt() ||
          rawCounter.toInt() != _queueCounter) {
        _log('state rejected: queue counter $rawCounter != $_queueCounter');
        return false;
      }
      remoteSnapshot = AriamiPlaybackSnapshot.fromJson(<String, dynamic>{
        ...data,
        'queue': _remoteQueue,
        'backingOrder': _remoteBackingOrder,
        if (_remoteSourceId != null) 'sourceId': _remoteSourceId,
      });
    } else {
      final raw = data['snapshot'];
      if (raw is Map) {
        remoteSnapshot = AriamiPlaybackSnapshot.fromJson(
          Map<String, dynamic>.from(raw),
        );
      }
    }
    _lastRevision = revision;
    remoteSnapshotAt = DateTime.now();
    _log('state applied: revision $revision, active $activeDeviceId, '
        'track ${remoteSnapshot?.currentTrackId}, '
        'playing ${remoteSnapshot?.isPlaying}');
    onChanged?.call();
    return true;
  }

  Future<bool> _readQueue(Map<String, dynamic> data) async {
    if (_hubProtocolVersion < AriamiConnectProtocol.v3) return false;
    final previousEpoch = ownerEpoch;
    final authority = await _acceptAuthority(data);
    if (!authority.accepted) return false;
    final rawCounter = data['queueCounter'];
    if (rawCounter is! num ||
        rawCounter != rawCounter.toInt() ||
        rawCounter.toInt() < 0) {
      return false;
    }
    final counter = rawCounter.toInt();
    if (ownerEpoch == previousEpoch && counter < _queueCounter) return false;
    final rawTracks = data['tracks'];
    if (rawTracks is! List ||
        rawTracks.length > AriamiPlaybackSnapshot.maxQueueLength) {
      return false;
    }
    final tracks = <Map<String, dynamic>>[];
    for (final rawTrack in rawTracks) {
      if (rawTrack is! Map) return false;
      final track = Map<String, dynamic>.from(rawTrack);
      if ((track['id'] as String? ?? '').isEmpty) return false;
      tracks.add(track);
    }
    final backingOrder =
        validateConnectBackingOrder(data['backingOrder'], tracks.length);
    _remoteQueue = List<Map<String, dynamic>>.unmodifiable(tracks);
    _remoteBackingOrder = backingOrder;
    _remoteSourceId = data['sourceId'] as String?;
    _queueCounter = counter;
    _log('queue applied: counter $counter, tracks ${tracks.length}, '
        'active $activeDeviceId');
    if (isThisDeviceActive) {
      final fingerprint = canonicalConnectQueueFingerprint(
        queue: _remoteQueue,
        backingOrder: _remoteBackingOrder,
        sourceId: _remoteSourceId,
      );
      _lastPublishedQueueFingerprint = fingerprint;
      if (_awaitingQueueFingerprint == fingerprint) {
        _awaitingQueueFingerprint = null;
        _sendSplitState(snapshotProvider());
      }
    }
    return true;
  }

  Future<({bool accepted, bool paused})> _acceptAuthority(
      Map<String, dynamic> data) async {
    final generation = _connectionGeneration;
    final rawEpoch = data['ownerEpoch'];
    final carriesOwner = data.containsKey('activeDeviceId');
    final incomingOwner =
        carriesOwner ? data['activeDeviceId'] as String? : activeDeviceId;

    // Older v2 hubs omit epochs. Keep that rolling-upgrade path working; it
    // cannot provide fencing, but upgraded hubs always include the field.
    if (rawEpoch == null) {
      if (carriesOwner) activeDeviceId = incomingOwner;
      return (accepted: true, paused: false);
    }
    if (rawEpoch is! num ||
        rawEpoch != rawEpoch.toInt() ||
        rawEpoch.toInt() < 0) {
      return (accepted: false, paused: false);
    }

    final incomingEpoch = rawEpoch.toInt();
    if (incomingEpoch < ownerEpoch) {
      _log('work rejected: owner epoch $incomingEpoch < $ownerEpoch');
      return (accepted: false, paused: false);
    }
    if (incomingEpoch == ownerEpoch &&
        carriesOwner &&
        activeDeviceId != null &&
        incomingOwner != activeDeviceId) {
      _log('work rejected: owner changed without advancing epoch $ownerEpoch');
      return (accepted: false, paused: false);
    }

    var paused = false;
    if (incomingEpoch > ownerEpoch &&
        activeDeviceId == deviceId &&
        incomingOwner != null &&
        incomingOwner != deviceId) {
      if (!await _pauseForNewOwner(incomingEpoch)) {
        return (accepted: false, paused: false);
      }
      if (generation != _connectionGeneration) {
        return (accepted: false, paused: false);
      }
      paused = true;
    }
    ownerEpoch = incomingEpoch;
    if (carriesOwner) activeDeviceId = incomingOwner;
    return (accepted: true, paused: paused);
  }

  Future<bool> _pauseForNewOwner(int epoch) async {
    if (_lastPausedOwnerEpoch >= epoch) return true;
    final inFlight = _formerOwnerPauseFuture;
    if (inFlight != null) {
      try {
        await inFlight;
      } catch (_) {
        return false;
      }
      return _lastPausedOwnerEpoch >= epoch;
    }

    final pause = Future<void>.sync(pauseForTransfer);
    _formerOwnerPauseFuture = pause;
    try {
      await pause;
      _lastPausedOwnerEpoch = epoch;
      return true;
    } catch (error) {
      errorMessage = 'Ariami Connect could not pause former playback: $error';
      onChanged?.call();
      return false;
    } finally {
      if (identical(_formerOwnerPauseFuture, pause)) {
        _formerOwnerPauseFuture = null;
      }
    }
  }

  Future<void> _runCommand(Map<String, dynamic> data) async {
    final commandId = data['commandId'] as String? ?? '';
    _log('command in: ${data['command']} from ${data['requestedBy']}');
    final authority = await _acceptAuthority(data);
    if (!authority.accepted) {
      _sendResult(
        commandId,
        ok: false,
        message: 'Playback ownership changed before that command arrived.',
      );
      return;
    }
    final previousResult = _handledCommandResults[commandId];
    if (commandId.isNotEmpty && previousResult != null) {
      _send(WsMessage(
        type: AriamiConnectMessageType.commandResult,
        data: previousResult,
      ));
      return;
    }
    try {
      final command = data['command'] as String? ?? '';
      if (!(authority.paused && command == AriamiConnectCommand.pause)) {
        await handleCommand(
          command,
          data['arguments'] is Map
              ? Map<String, dynamic>.from(data['arguments'] as Map)
              : const <String, dynamic>{},
        );
      }
      final commandEpoch = (data['ownerEpoch'] as num?)?.toInt();
      if (commandEpoch == null || commandEpoch == ownerEpoch) {
        if (isThisDeviceActive) publishState();
      }
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
      final authority = await _acceptAuthority(<String, dynamic>{
        ...data,
        'activeDeviceId': sourceId,
      });
      if (!authority.accepted) return;
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
          data: <String, dynamic>{
            'transferId': transferId,
            'ok': true,
            'ownerEpoch': ownerEpoch,
          },
        ));
      } catch (error) {
        _send(WsMessage(
          type: AriamiConnectMessageType.transferResult,
          data: <String, dynamic>{
            'transferId': transferId,
            'ok': false,
            'message': '$error',
            'ownerEpoch': ownerEpoch,
          },
        ));
      } finally {
        isApplyingRemoteState = false;
        onChanged?.call();
      }
      return;
    }

    if (phase != 'commit') return;
    final authority = await _acceptAuthority(<String, dynamic>{
      ...data,
      'activeDeviceId': targetId,
    });
    if (!authority.accepted) return;
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
      if (_hubProtocolVersion >= AriamiConnectProtocol.v3) {
        _remoteQueue = snapshot.queue;
        _remoteBackingOrder = snapshot.backingOrder;
        _remoteSourceId = snapshot.sourceId;
      }
    }
    final queueCounter = (data['queueCounter'] as num?)?.toInt();
    if (queueCounter != null) _queueCounter = queueCounter;
    final revision = (data['stateRevision'] as num?)?.toInt() ??
        (data['revision'] as num?)?.toInt();
    if (revision != null && revision > _lastRevision) {
      _lastRevision = revision;
    }
    if (targetId == deviceId) {
      if (snapshot == null) return;
      _lastPublishedQueueFingerprint = snapshot.queueFingerprint;
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
    } else if (sourceId == deviceId && !authority.paused) {
      await pauseForTransfer();
    }
    onChanged?.call();
  }

  void publishState({bool activate = false}) {
    if (activate) {
      requestLocalTakeover();
      return;
    }
    _scheduleStatePublish(activate: false);
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
    final discreteFingerprint = _discreteFingerprint(snapshot);
    final queueChanged =
        snapshot.queueFingerprint != _lastPublishedQueueFingerprint;
    final discreteChanged =
        discreteFingerprint != _lastPublishedDiscreteFingerprint;
    if (activate || queueChanged || discreteChanged) {
      _progressPublishTimer?.cancel();
      _progressPublishTimer = null;
      _publishSnapshot(snapshot, activate: activate);
      return;
    }
    _scheduleStatePublish(activate: false, snapshot: snapshot);
  }

  void _scheduleStatePublish({
    required bool activate,
    AriamiPlaybackSnapshot? snapshot,
  }) {
    if (!isConnected || isApplyingRemoteState) return;
    final current = snapshot ?? snapshotProvider();
    if (activate) {
      _publishSnapshot(current, activate: true);
      return;
    }
    final discreteFingerprint = _discreteFingerprint(current);
    if (current.queueFingerprint != _lastPublishedQueueFingerprint ||
        discreteFingerprint != _lastPublishedDiscreteFingerprint) {
      _progressPublishTimer?.cancel();
      _progressPublishTimer = null;
      _publishSnapshot(current, activate: false);
      return;
    }
    final last = _lastStatePublishedAt;
    final elapsed = last == null
        ? progressPublishInterval
        : DateTime.now().difference(last);
    if (elapsed >= progressPublishInterval) {
      _publishSnapshot(current, activate: false);
      return;
    }
    if (_progressPublishTimer?.isActive ?? false) return;
    _progressPublishTimer = timerFactory(progressPublishInterval - elapsed, () {
      _progressPublishTimer = null;
      if (!isConnected || isApplyingRemoteState) return;
      _publishSnapshot(snapshotProvider(), activate: false);
    });
  }

  void _publishSnapshot(AriamiPlaybackSnapshot snapshot,
      {required bool activate}) {
    _log('publish: activate $activate, track ${snapshot.currentTrackId}, '
        'playing ${snapshot.isPlaying}, thinksActive $isThisDeviceActive');
    if (_hubProtocolVersion >= AriamiConnectProtocol.v3) {
      final fingerprint = snapshot.queueFingerprint;
      final queueChanged = fingerprint != _lastPublishedQueueFingerprint;
      if (activate || queueChanged) {
        // The hub echoes connect_queue to acknowledge its canonical counter.
        // Repeating the whole queue on every tick until that echo arrives
        // would restore the per-progress full-queue cost this slice removes.
        // Takeovers still resend, because the hub commits ownership from the
        // queue message itself.
        if (!activate && _awaitingQueueFingerprint == fingerprint) return;
        _awaitingQueueFingerprint = fingerprint;
        _send(WsMessage(
          type: AriamiConnectMessageType.queue,
          data: <String, dynamic>{
            'activate': activate,
            'tracks': snapshot.queue,
            'backingOrder': snapshot.backingOrder,
            if (snapshot.sourceId != null) 'sourceId': snapshot.sourceId,
            'queueCounter': queueChanged ? _queueCounter + 1 : _queueCounter,
            'ownerEpoch': ownerEpoch,
          },
        ));
        return;
      }
      _sendSplitState(snapshot);
      return;
    }
    _send(WsMessage(
      type: AriamiConnectMessageType.state,
      data: <String, dynamic>{
        'activate': activate,
        'snapshot': snapshot.toJson(),
        'ownerEpoch': ownerEpoch,
      },
    ));
    _recordPublishedState(snapshot);
  }

  void _sendSplitState(AriamiPlaybackSnapshot snapshot) {
    _outboundStateRevision++;
    _send(WsMessage(
      type: AriamiConnectMessageType.state,
      data: <String, dynamic>{
        'queueCounter': _queueCounter,
        'currentIndex': snapshot.currentIndex,
        'positionMs': snapshot.positionMs,
        'durationMs': snapshot.durationMs,
        'isPlaying': snapshot.isPlaying,
        'shuffle': snapshot.shuffle,
        'repeatMode': snapshot.repeatMode,
        'volume': snapshot.volume,
        'stateRevision': _outboundStateRevision,
        'ownerEpoch': ownerEpoch,
      },
    ));
    _recordPublishedState(snapshot);
  }

  void _recordPublishedState(AriamiPlaybackSnapshot snapshot) {
    _lastPublishedQueueFingerprint = snapshot.queueFingerprint;
    _lastPublishedDiscreteFingerprint = _discreteFingerprint(snapshot);
    _lastStatePublishedAt = DateTime.now();
  }

  String _discreteFingerprint(AriamiPlaybackSnapshot snapshot) => jsonEncode(
        <String, dynamic>{
          'queue': snapshot.queueFingerprint,
          'currentIndex': snapshot.currentIndex,
          'durationMs': snapshot.durationMs,
          'isPlaying': snapshot.isPlaying,
          'shuffle': snapshot.shuffle,
          'repeatMode': snapshot.repeatMode,
          'volume': snapshot.volume,
        },
      );

  void _resetSplitState() {
    _progressPublishTimer?.cancel();
    _progressPublishTimer = null;
    _queueCounter = 0;
    _outboundStateRevision = 0;
    _remoteQueue = const <Map<String, dynamic>>[];
    _remoteBackingOrder = const <int>[];
    _remoteSourceId = null;
    _lastPublishedQueueFingerprint = null;
    _lastPublishedDiscreteFingerprint = null;
    _awaitingQueueFingerprint = null;
    _lastStatePublishedAt = null;
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
          'ownerEpoch': ownerEpoch,
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
      data: <String, dynamic>{
        'targetDeviceId': targetDeviceId,
        'ownerEpoch': ownerEpoch,
      },
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
    if (_closedByUser || _reconnectSuppressed || _baseUrl == null) return;
    if (_connecting) return;
    if (!isConnected) {
      await _open();
      return;
    }

    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _welcomeTimer?.cancel();
    _livenessTimer?.cancel();
    _backoffResetTimer?.cancel();
    _pingTimer = null;
    _welcomeTimer = null;
    _livenessTimer = null;
    _backoffResetTimer = null;
    _isWelcomed = false;
    _connectionGeneration++;
    _lastRevision = -1;
    _hubProtocolVersion = 1;
    _resetSplitState();
    ownerEpoch = 0;
    activeDeviceId = null;
    _lastPausedOwnerEpoch = -1;
    _takeoverSentOnCurrentConnection = false;
    isConnected = false;

    final subscription = _subscription;
    final channel = _channel;
    _subscription = null;
    _channel = null;
    await Future.wait(<Future<void>>[
      _cancelSubscription(subscription, refreshCloseTimeout),
      _closeChannel(
        channel,
        1000,
        'Refreshing Connect state',
        refreshCloseTimeout,
      ),
    ]);
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
      'ownerEpoch': ownerEpoch,
      'activeDeviceId': activeDeviceId,
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
    if (pending.attempts == 0) {
      pending.message = WsMessage(
        type: pending.message.type,
        data: <String, dynamic>{
          ...?pending.message.data,
          'ownerEpoch': ownerEpoch,
        },
      );
    }
    pending.attempts += 1;
    _send(pending.message);
    pending.retryTimer = timerFactory(commandAckTimeout, () {
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
    final closeCode = source?.closeCode;
    final closeReason = source?.closeReason;
    final authenticationRequired = closeCode == 4001;
    final replaced = closeCode == 4000 &&
        (closeReason?.toLowerCase().contains('replaced') ?? false);
    final wasConnected = isConnected;
    _connectionGeneration++;
    isConnected = false;
    _isWelcomed = false;
    _receivedInboundOnCurrentConnection = false;
    _pingTimer?.cancel();
    _welcomeTimer?.cancel();
    _livenessTimer?.cancel();
    _backoffResetTimer?.cancel();
    _pingTimer = null;
    _welcomeTimer = null;
    _livenessTimer = null;
    _backoffResetTimer = null;
    final subscription = _subscription;
    _subscription = null;
    _channel = null;
    unawaited(_cancelSubscription(subscription, disposeTimeout));
    unawaited(_closeChannel(
      source,
      1001,
      'Connect transport disconnected',
      disposeTimeout,
    ));
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
    _hubProtocolVersion = 1;
    _resetSplitState();
    ownerEpoch = 0;
    activeDeviceId = null;
    _lastPausedOwnerEpoch = -1;
    // A takeover sent just before the drop may never have been acknowledged.
    // Keep the intent, but allow the replacement socket to publish it again.
    _takeoverSentOnCurrentConnection = false;
    if (authenticationRequired) {
      _reconnectSuppressed = true;
      _sessionToken = null;
      errorMessage = 'Your session expired. Please sign in again.';
    } else if (replaced) {
      _reconnectSuppressed = true;
    }
    if (wasConnected) _log('disconnected');
    if (wasConnected || authenticationRequired) onChanged?.call();
    if (authenticationRequired) onAuthenticationRequired?.call();
    if (_closedByUser || _reconnectSuppressed) return;
    _reconnectTimer?.cancel();
    final seconds = min(30, 1 << min(_reconnectAttempt++, 5));
    _reconnectTimer = timerFactory(Duration(seconds: seconds), _open);
  }

  Future<void> dispose() async {
    _closedByUser = true;
    _connectionGeneration++;
    _reconnectSuppressed = true;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _welcomeTimer?.cancel();
    _livenessTimer?.cancel();
    _backoffResetTimer?.cancel();
    _progressPublishTimer?.cancel();
    for (final pending in _pendingCommands.values) {
      pending.retryTimer?.cancel();
    }
    _pendingCommands.clear();
    _takeoverRequested = false;
    _takeoverSentOnCurrentConnection = false;
    final subscription = _subscription;
    final channel = _channel;
    _subscription = null;
    _channel = null;
    isConnected = false;
    await Future.wait(<Future<void>>[
      _cancelSubscription(subscription, disposeTimeout),
      _closeChannel(channel, 1000, 'Client closed', disposeTimeout),
    ]);
  }

  Future<void> _cancelSubscription(
    StreamSubscription<dynamic>? subscription,
    Duration timeout,
  ) async {
    if (subscription == null) return;
    try {
      await subscription.cancel().timeout(timeout);
    } catch (_) {
      // Teardown is best-effort. A replacement socket must not wait forever for
      // a transport that has already stopped delivering events.
    }
  }

  Future<void> _closeChannel(
    WebSocketChannel? channel,
    int code,
    String reason,
    Duration timeout,
  ) async {
    if (channel == null) return;
    try {
      await channel.sink.close(code, reason).timeout(timeout);
    } catch (_) {
      // See [_cancelSubscription]: close acknowledgement is bounded as well.
    }
  }
}

class _PendingOutboundCommand {
  _PendingOutboundCommand({required this.message});

  WsMessage message;
  int attempts = 0;
  Timer? retryTimer;
}
