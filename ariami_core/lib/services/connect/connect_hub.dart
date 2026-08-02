import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:ariami_core/models/connect_models.dart';
import 'package:ariami_core/models/websocket_models.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const kConnectOwnerReclaimGrace = Duration(seconds: 20);
const kConnectRecentControllerWindow = Duration(seconds: 120);

DateTime _connectUtcNow() => DateTime.now().toUtc();

/// Authenticated, in-memory rendezvous for Ariami Connect.
///
/// Playback remains owned and persisted by clients. After a server restart,
/// clients reconnect and the active device republishes its state.
class AriamiConnectHub {
  AriamiConnectHub({
    this.disconnectGracePeriod = kConnectOwnerReclaimGrace,
    this.recentControllerWindow = kConnectRecentControllerWindow,
    this.commandTimeout = const Duration(seconds: 10),
    this.transferTimeout = const Duration(seconds: 30),
    this.staleTimeout = const Duration(seconds: 90),
    this.sweepInterval = const Duration(seconds: 30),
    this.protocolV3Enabled = true,
    this.maxPendingCommands = kMaxPendingConnectCommands,
    this.maxCommandDeliveries = 4,
    DateTime Function()? now,
    Timer Function(Duration, void Function())? timerFactory,
  })  : _now = now ?? _connectUtcNow,
        _timerFactory = timerFactory ?? Timer.new;

  /// Gives a playback client enough time to reconnect after a transient
  /// WebSocket drop before its controller takes over the session.
  final Duration disconnectGracePeriod;

  /// How recently a device must have issued an accepted command in this
  /// session before automatic failover may let it inherit playing state.
  final Duration recentControllerWindow;

  /// How long a relayed command may wait for the active device's result
  /// before the requester is told the device is unreachable. Long enough for
  /// a slow track load, short enough that tapping play on a dead device does
  /// not fail silently.
  final Duration commandTimeout;

  /// Bounds how long a target may remain prepared without a commit. Expiry
  /// explicitly cancels the prepare so the target can restore local playback.
  final Duration transferTimeout;

  /// Bounded command retention prevents one controller from exhausting the
  /// account-scoped session while results are outstanding.
  final int maxPendingCommands;

  /// Initial delivery plus retained-payload redeliveries to the active device.
  final int maxCommandDeliveries;

  /// How long a peer may go without any inbound traffic before the sweep
  /// treats its socket as dead and evicts it. This is a backstop for sockets
  /// that never deliver a close event (a killed app, a dropped Wi-Fi radio).
  /// Clients ping every 20s and the separate `ConnectionManager` already
  /// evicts stale presence at 60s, so this must sit comfortably above both:
  /// the hub is the outermost layer and must never race either of them into
  /// evicting a device that is merely idle, not actually gone.
  final Duration staleTimeout;

  /// How often the stale-peer sweep runs.
  final Duration sweepInterval;

  /// Server-side rollout switch consulted whenever a peer negotiates.
  /// Existing clients need no redeployment when v3 is disabled.
  bool protocolV3Enabled;

  final Map<WebSocketChannel, _ConnectPeer> _peers = {};
  final Map<WebSocketChannel, Map<String, dynamic>> _pendingHellos = {};
  final Map<String, _ConnectSession> _sessions = {};
  final DateTime Function() _now;
  final Timer Function(Duration, void Function()) _timerFactory;
  Timer? _sweepTimer;

  /// Invoked after a device successfully renames itself, so the server can
  /// persist the new name and refresh presence/session records. The hub has
  /// already updated its own peers and broadcast the new device list.
  void Function(String userId, String deviceId, String name)? onDeviceRenamed;

  void register(
    WebSocketChannel socket, {
    required String userId,
    required String deviceId,
    required String deviceName,
    required String clientType,
  }) {
    if (deviceId.isEmpty) return;
    final hello = _pendingHellos.remove(socket);
    final duplicates = _peers.entries
        .where((entry) =>
            entry.value.userId == userId && entry.value.deviceId == deviceId)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final oldSocket in duplicates) {
      _peers.remove(oldSocket);
      oldSocket.sink.close(4000, 'Replaced by a newer connection');
    }
    final peer = _ConnectPeer(
      userId: userId,
      deviceId: deviceId,
      deviceName: deviceName,
      clientType: clientType,
      connectedAt: _now(),
      lastSeen: _now(),
      protocolVersion: _negotiateProtocolVersion(hello),
      supportedCommands: _readSupportedCommands(hello),
    );
    _peers[socket] = peer;
    // Lazily start the sweep on the first peer instead of in the constructor:
    // the hub is a field initializer, so a constructor-started timer would
    // leak into every server instance (and every test) whether or not
    // Connect is ever used.
    _sweepTimer ??= Timer.periodic(sweepInterval, (_) => _sweepStalePeers());
    final session = _sessions[userId];
    if (session?.activeDeviceId == deviceId) {
      // The player came back during the grace period. Keep it as the owner and
      // cancel any automatic handoff that raced with its reconnect.
      session!.disconnectTimer?.cancel();
      session.disconnectTimer = null;
      session.failover = null;
      final automaticTransfers = session.pendingTransfers.values
          .where((transfer) =>
              transfer.automatic && transfer.sourceDeviceId == deviceId)
          .toList(growable: false);
      for (final transfer in automaticTransfers) {
        _cancelTransfer(
          userId,
          session,
          transfer,
          reason: 'owner_reclaimed',
        );
      }
    }
    // Identify is authenticated asynchronously by the server. A client may
    // have already sent connect_hello while that validation was in flight, so
    // recognized playback clients are made ready here as well.
    if (const {'desktop', 'mobile', 'tv'}.contains(clientType)) {
      peer.canPlay = hello?['canPlay'] as bool? ?? true;
      _sendWelcome(socket, peer);
      if (session?.activeDeviceId == deviceId) {
        _redeliverPendingCommands(session!, socket, peer);
      }
      if (session != null) {
        _redeliverFormerOwnerPause(userId, session, deviceId);
      }
      _broadcastDevices(userId);
    }
  }

  void unregister(WebSocketChannel socket) {
    _pendingHellos.remove(socket);
    final peer = _peers.remove(socket);
    if (peer != null) {
      final session = _sessions[peer.userId];
      final abandoned = session?.pendingTransfers.values
              .where((transfer) =>
                  transfer.targetDeviceId == peer.deviceId ||
                  identical(transfer.requester, socket))
              .toList(growable: false) ??
          const <_PendingTransfer>[];
      for (final transfer in abandoned) {
        _cancelTransfer(
          peer.userId,
          session!,
          transfer,
          reason: 'disconnect',
          notifyTarget: transfer.targetDeviceId != peer.deviceId,
        );
        if (transfer.automatic) {
          _continueAutomaticFailover(peer.userId, session, transfer);
        } else {
          _sendError(transfer.requester, 'DEVICE_OFFLINE',
              'A device disconnected during handoff.');
        }
      }
      if (session?.activeDeviceId == peer.deviceId &&
          session?.snapshot?.queue.isNotEmpty == true) {
        _scheduleDisconnectFailover(peer.userId, peer.deviceId, session!);
      } else {
        _broadcastDevices(peer.userId);
      }
    }
    if (_peers.isEmpty) {
      _sweepTimer?.cancel();
      _sweepTimer = null;
    }
  }

  /// Marks [socket] as alive. Called for every inbound message it sends,
  /// including app-level `ping`, which is answered by the server's WebSocket
  /// layer and never reaches [handle] — without this the sweep would evict a
  /// device that is idle-but-connected as if it had gone dark.
  void touch(WebSocketChannel socket) {
    _peers[socket]?.lastSeen = _now();
  }

  /// Backstop for peers whose socket died without ever delivering a close
  /// event. Ordinary disconnects already go through [unregister] via the
  /// transport; this only catches the ones the transport never told us about.
  void _sweepStalePeers() {
    final now = _now();
    // Snapshot first: unregister() mutates _peers, so iterating the live map
    // while removing from it would skip entries or throw.
    final stale = _peers.entries
        .where((entry) => now.difference(entry.value.lastSeen) > staleTimeout)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final socket in stale) {
      unregister(socket);
      socket.sink.close(4000, 'Connection timed out');
    }
    if (_peers.isEmpty) {
      _sweepTimer?.cancel();
      _sweepTimer = null;
    }
  }

  /// Stops the sweep timer and drops all peers. Call this from the server's
  /// shutdown path so the periodic timer never outlives the server instance.
  void dispose() {
    _sweepTimer?.cancel();
    _sweepTimer = null;
    // Sessions own a failover timer and a timeout per pending transfer. Those
    // outlive _peers.clear() and would fire against a torn-down hub.
    for (final session in _sessions.values) {
      session.disconnectTimer?.cancel();
      for (final transfer in session.pendingTransfers.values) {
        transfer.timeout?.cancel();
      }
      for (final pending in session.pendingCommands.values) {
        pending.timeout?.cancel();
      }
      for (final pending in session.pendingFormerOwnerPauses.values) {
        pending.timeout?.cancel();
      }
    }
    _sessions.clear();
    _pendingHellos.clear();
    _peers.clear();
  }

  void _scheduleDisconnectFailover(
      String userId, String sourceDeviceId, _ConnectSession session) {
    session.disconnectTimer?.cancel();
    session.failover = null;
    session.disconnectTimer = _timerFactory(disconnectGracePeriod, () {
      session.disconnectTimer = null;
      if (session.activeDeviceId != sourceDeviceId ||
          _peerForDevice(userId, sourceDeviceId) != null) {
        return;
      }
      _beginDisconnectFailover(userId, sourceDeviceId, session);
    });
  }

  void _beginDisconnectFailover(
      String userId, String sourceDeviceId, _ConnectSession session) {
    final now = _now();
    session.lastCommandAtByDevice.removeWhere(
      (_, issuedAt) => !_isRecentController(issuedAt, now),
    );
    final candidates = _peers.entries
        .where((entry) =>
            entry.value.userId == userId &&
            entry.value.canPlay &&
            entry.value.deviceId != sourceDeviceId)
        .map((entry) => _FailoverCandidate(
              deviceId: entry.value.deviceId,
              connectedAt: entry.value.connectedAt,
              lastCommandAt:
                  session.lastCommandAtByDevice[entry.value.deviceId],
            ))
        .toList(growable: false)
      ..sort((a, b) {
        final aRecent = a.lastCommandAt != null;
        final bRecent = b.lastCommandAt != null;
        if (aRecent != bRecent) return aRecent ? -1 : 1;
        if (aRecent) {
          final commandOrder = b.lastCommandAt!.compareTo(a.lastCommandAt!);
          if (commandOrder != 0) return commandOrder;
        }
        final connectionOrder = b.connectedAt.compareTo(a.connectedAt);
        return connectionOrder != 0
            ? connectionOrder
            : a.deviceId.compareTo(b.deviceId);
      });
    session.failover = _PendingFailover(
      sourceDeviceId: sourceDeviceId,
      remainingCandidates: List<_FailoverCandidate>.of(candidates),
    );
    _tryNextFailoverCandidate(userId, session);
  }

  void _tryNextFailoverCandidate(String userId, _ConnectSession session) {
    final failover = session.failover;
    if (failover == null ||
        session.activeDeviceId != failover.sourceDeviceId ||
        _peerForDevice(userId, failover.sourceDeviceId) != null) {
      session.failover = null;
      return;
    }
    while (failover.remainingCandidates.isNotEmpty) {
      final candidate = failover.remainingCandidates.removeAt(0);
      final target = _peerForDevice(userId, candidate.deviceId);
      if (target == null || !target.peer.canPlay) continue;
      final snapshot = session.snapshot;
      if (snapshot == null || snapshot.queue.isEmpty) break;
      final now = _now();
      final preparedSnapshot = !_isRecentController(
              candidate.lastCommandAt, now)
          ? snapshot.compensated(now).copyWith(isPlaying: false, updatedAt: now)
          : snapshot;
      _handleTransfer(
        target.socket,
        target.peer,
        <String, dynamic>{
          'targetDeviceId': target.peer.deviceId,
          'ownerEpoch': session.ownerEpoch,
        },
        automatic: true,
        automaticSnapshot: preparedSnapshot,
      );
      return;
    }
    _settleFailedFailover(userId, session);
  }

  bool _isRecentController(DateTime? issuedAt, DateTime now) {
    if (issuedAt == null) return false;
    final age = now.difference(issuedAt);
    return !age.isNegative && age <= recentControllerWindow;
  }

  void _continueAutomaticFailover(
      String userId, _ConnectSession session, _PendingTransfer transfer) {
    final failover = session.failover;
    if (!transfer.automatic ||
        failover == null ||
        failover.sourceDeviceId != transfer.sourceDeviceId) {
      return;
    }
    _tryNextFailoverCandidate(userId, session);
  }

  void _settleFailedFailover(String userId, _ConnectSession session) {
    final failover = session.failover;
    if (failover == null ||
        session.activeDeviceId != failover.sourceDeviceId ||
        _peerForDevice(userId, failover.sourceDeviceId) != null) {
      session.failover = null;
      return;
    }
    final now = _now();
    final snapshot = session.snapshot;
    if (snapshot != null) {
      session.snapshot =
          snapshot.compensated(now).copyWith(isPlaying: false, updatedAt: now);
    }
    _commitOwnership(
      userId,
      session,
      null,
      requestedBy: 'automatic_failover',
    );
    session.revision++;
    _broadcastState(userId, session);
    _broadcastDevices(userId);
  }

  bool handle(WebSocketChannel socket, WsMessage message) {
    // Any traffic on this socket proves it is alive, regardless of the
    // message type or whether it turns out to be one Connect handles.
    touch(socket);
    if (!message.type.startsWith('connect_')) return false;
    final data = message.data ?? const <String, dynamic>{};
    try {
      validateConnectJsonShape(data);
    } on FormatException catch (error) {
      _sendError(socket, 'INVALID_PAYLOAD', error.message);
      return true;
    }
    final peer = _peers[socket];
    if (peer == null) {
      // Authentication validation is asynchronous. Retain a hello that races
      // ahead of registration so the first welcome can still be negotiated.
      if (message.type == AriamiConnectMessageType.hello) {
        _pendingHellos[socket] = Map<String, dynamic>.from(data);
        return true;
      }
      return false;
    }
    switch (message.type) {
      case AriamiConnectMessageType.hello:
        peer.canPlay = data['canPlay'] as bool? ?? true;
        peer.protocolVersion = _negotiateProtocolVersion(data);
        peer.supportedCommands = _readSupportedCommands(data);
        _sendWelcome(socket, peer);
        _broadcastDevices(peer.userId);
      case AriamiConnectMessageType.queue:
        _handleQueue(socket, peer, data);
      case AriamiConnectMessageType.state:
        _handleState(socket, peer, data);
      case AriamiConnectMessageType.command:
        _handleCommand(socket, peer, data);
      case AriamiConnectMessageType.commandResult:
        _handleCommandResult(peer, data);
      case AriamiConnectMessageType.transfer:
        _handleTransfer(socket, peer, data);
      case AriamiConnectMessageType.transferResult:
        _handleTransferResult(peer, data);
      case AriamiConnectMessageType.rename:
        _handleRename(socket, peer, data);
      default:
        _sendError(
            socket, 'UNSUPPORTED_MESSAGE', 'Unsupported Connect message.');
    }
    return true;
  }

  void _handleState(
      WebSocketChannel socket, _ConnectPeer peer, Map<String, dynamic> data) {
    if (peer.protocolVersion >= AriamiConnectProtocol.v3) {
      _handleSplitState(socket, peer, data);
      return;
    }
    try {
      final raw = data['snapshot'];
      final normalized = validateConnectSnapshotPayload(raw);
      final parsed = AriamiPlaybackSnapshot.fromJson(
        normalized,
      );
      final snapshot = AriamiPlaybackSnapshot.fromJson(parsed.toJson())
          .copyWith(updatedAt: _now());
      final activate = data['activate'] as bool? ?? false;
      final session = _sessions.putIfAbsent(peer.userId, _ConnectSession.new);
      if (!_acceptEpoch(session, data)) {
        _sendAuthoritativeState(socket, session);
        return;
      }
      final previousActive = session.activeDeviceId;
      if (session.activeDeviceId == null || activate) {
        _commitOwnership(
          peer.userId,
          session,
          peer.deviceId,
          requestedBy: peer.deviceId,
        );
      }
      // Inactive devices cannot overwrite the session being remotely
      // controlled. Answer with the authoritative state instead of dropping
      // silently, so a device that wrongly believes it is active resyncs
      // within one publish cycle instead of diverging forever.
      if (session.activeDeviceId != peer.deviceId) {
        _sendAuthoritativeState(socket, session);
        return;
      }
      final previousSnapshot = session.snapshot;
      final queueChanged = _adoptQueue(session, snapshot);
      _adoptSemanticGeneration(
        session,
        data,
        fallbackChanged:
            queueChanged || _semanticStateChanged(previousSnapshot, snapshot),
      );
      session.snapshot = snapshot;
      session.revision++;
      if (queueChanged) _broadcastQueue(peer.userId, session);
      _broadcastState(peer.userId, session, except: socket);
      if (activate && previousActive != session.activeDeviceId) {
        _broadcastDevices(peer.userId);
      }
    } on FormatException catch (error) {
      _sendError(socket, 'INVALID_STATE', error.message);
    }
  }

  void _handleQueue(
      WebSocketChannel socket, _ConnectPeer peer, Map<String, dynamic> data) {
    if (peer.protocolVersion < AriamiConnectProtocol.v3) {
      _sendError(socket, 'UNSUPPORTED_MESSAGE',
          'Split queue messages require Connect protocol v3.');
      return;
    }
    try {
      final rawTracks = data['tracks'];
      if (rawTracks is! List) throw const FormatException('Missing tracks');
      if (rawTracks.length > AriamiPlaybackSnapshot.maxQueueLength) {
        throw const FormatException('Connect queue is too large');
      }
      final tracks =
          rawTracks.map(validateConnectTrackPayload).toList(growable: false);
      final backingOrder =
          validateConnectBackingOrder(data['backingOrder'], tracks.length);
      final sourceId = data['sourceId'] as String?;
      if (sourceId != null && sourceId.length > kMaxConnectSourceIdLength) {
        throw const FormatException('Invalid Connect source');
      }
      final session = _sessions.putIfAbsent(peer.userId, _ConnectSession.new);
      if (!_acceptEpoch(session, data)) {
        _sendAuthoritativeState(socket, session);
        return;
      }
      final activate = data['activate'] as bool? ?? false;
      final previousActive = session.activeDeviceId;
      if (session.activeDeviceId == null || activate) {
        _commitOwnership(
          peer.userId,
          session,
          peer.deviceId,
          requestedBy: peer.deviceId,
        );
      }
      if (session.activeDeviceId != peer.deviceId) {
        _sendAuthoritativeState(socket, session);
        return;
      }

      final queue = _ConnectQueueData(
        tracks: List<Map<String, dynamic>>.unmodifiable(tracks),
        backingOrder: backingOrder,
        sourceId: sourceId,
      );
      if (session.queue?.fingerprint != queue.fingerprint) {
        session.queue = queue;
        session.queueCounter++;
        _adoptSemanticGeneration(
          session,
          data,
          fallbackChanged: true,
        );
      } else {
        session.queue = queue;
        _adoptSemanticGeneration(
          session,
          data,
          fallbackChanged: false,
        );
      }
      // Echo the canonical counter to the owner. The sender deliberately waits
      // for this acknowledgement before publishing state, so a reconnect or
      // same-fingerprint takeover cannot guess the hub's counter.
      _broadcastQueue(peer.userId, session);
      if (activate && previousActive != session.activeDeviceId) {
        _broadcastDevices(peer.userId);
      }
    } on FormatException catch (error) {
      _sendError(socket, 'INVALID_QUEUE', error.message);
    } on TypeError {
      _sendError(socket, 'INVALID_QUEUE', 'Invalid Connect queue metadata.');
    }
  }

  void _handleSplitState(
      WebSocketChannel socket, _ConnectPeer peer, Map<String, dynamic> data) {
    try {
      final session = _sessions.putIfAbsent(peer.userId, _ConnectSession.new);
      if (!_acceptEpoch(session, data)) {
        _sendAuthoritativeState(socket, session);
        return;
      }
      if (session.activeDeviceId != peer.deviceId) {
        _sendAuthoritativeState(socket, session);
        return;
      }
      final queue = session.queue;
      final rawQueueCounter = data['queueCounter'];
      if (queue == null ||
          rawQueueCounter is! num ||
          rawQueueCounter != rawQueueCounter.toInt() ||
          rawQueueCounter.toInt() != session.queueCounter) {
        _sendAuthoritativeState(socket, session);
        return;
      }
      final snapshot = AriamiPlaybackSnapshot.fromJson(<String, dynamic>{
        ...data,
        'queue': queue.tracks,
        'backingOrder': queue.backingOrder,
        if (queue.sourceId != null) 'sourceId': queue.sourceId,
      }).copyWith(updatedAt: _now());
      _adoptSemanticGeneration(
        session,
        data,
        fallbackChanged: _semanticStateChanged(session.snapshot, snapshot),
      );
      session.snapshot = snapshot;
      session.revision++;
      _broadcastState(peer.userId, session, except: socket);
    } on FormatException catch (error) {
      _sendError(socket, 'INVALID_STATE', error.message);
    }
  }

  bool _adoptQueue(_ConnectSession session, AriamiPlaybackSnapshot snapshot) {
    final queue = _ConnectQueueData(
      tracks: snapshot.queue,
      // A v2 snapshot never establishes backing order; it was not part of the
      // maintained v2 wire contract and cannot be inferred after shuffling.
      backingOrder: List<int>.generate(snapshot.queue.length, (index) => index),
      sourceId: snapshot.sourceId,
    );
    final changed = session.queue?.fingerprint != queue.fingerprint;
    session.queue = queue;
    if (changed) session.queueCounter++;
    return changed;
  }

  void _handleCommand(
      WebSocketChannel socket, _ConnectPeer peer, Map<String, dynamic> data) {
    final commandId = data['commandId'] as String? ?? '';
    final session = _sessions[peer.userId];
    if (commandId.isEmpty || commandId.length > kMaxConnectCommandIdLength) {
      _sendCommandResult(
        socket,
        commandId,
        ok: false,
        code: 'INVALID_COMMAND_ID',
        message: 'That command identifier is invalid.',
        remember: false,
        ownerEpoch: session?.ownerEpoch,
        activeDeviceId: session?.activeDeviceId,
      );
      return;
    }
    if (session != null && !_acceptEpoch(session, data)) {
      _sendCommandResult(
        socket,
        commandId,
        ok: false,
        code: 'STALE_OWNER',
        message: 'Playback ownership changed before that command arrived.',
        ownerEpoch: session.ownerEpoch,
        activeDeviceId: session.activeDeviceId,
      );
      return;
    }
    final completed = session?.completedCommands[commandId];
    if (completed != null) {
      if (completed.requesterDeviceId != peer.deviceId) {
        _sendCommandResult(
          socket,
          commandId,
          ok: false,
          code: 'COMMAND_ID_COLLISION',
          message: 'That command identifier is already in use.',
          remember: false,
          ownerEpoch: session?.ownerEpoch,
          activeDeviceId: session?.activeDeviceId,
        );
        return;
      }
      _send(socket, AriamiConnectMessageType.commandResult, completed.result);
      return;
    }
    final existing = session?.pendingCommands[commandId];
    if (existing != null) {
      if (existing.requesterDeviceId != peer.deviceId) {
        _sendCommandResult(
          socket,
          commandId,
          ok: false,
          code: 'COMMAND_ID_COLLISION',
          message: 'That command identifier is already in use.',
          remember: false,
          ownerEpoch: session?.ownerEpoch,
          activeDeviceId: session?.activeDeviceId,
        );
        return;
      }
      final retryOnly = data['retry'] == true &&
          data.keys.every(const <String>{'commandId', 'retry'}.contains);
      if (!retryOnly) {
        // Older clients replay the full payload. It remains supported only
        // when it is byte-for-byte equivalent to the immutable retained work.
        final command = data['command'] as String? ?? '';
        try {
          final arguments = validateConnectCommandArguments(
            command,
            data['arguments'] ?? const <String, dynamic>{},
          );
          final fingerprint = jsonEncode(<String, dynamic>{
            'command': command,
            'arguments': arguments,
          });
          if (fingerprint != existing.fingerprint) {
            throw const FormatException('Command payload changed');
          }
        } on FormatException {
          _sendCommandResult(
            socket,
            commandId,
            ok: false,
            code: 'COMMAND_ID_COLLISION',
            message: 'That command identifier was reused for different work.',
            remember: false,
            ownerEpoch: session?.ownerEpoch,
            activeDeviceId: session?.activeDeviceId,
          );
          return;
        }
      }
      // A controller can reconnect and retry through its newest socket. The
      // hub redelivers its retained full payload; the target deduplicates it.
      existing.requester = socket;
      _deliverPendingCommand(session!, commandId, existing);
      return;
    }

    if (data['retry'] == true) {
      // Deliberately not remembered: the controller answers this by replaying
      // its retained full payload under the same id, and a memoized failure
      // would make the hub reject that replay instead of running it.
      _sendCommandResult(
        socket,
        commandId,
        ok: false,
        code: 'UNKNOWN_COMMAND',
        message: 'That retained command is no longer available.',
        remember: false,
        ownerEpoch: session?.ownerEpoch,
        activeDeviceId: session?.activeDeviceId,
      );
      return;
    }

    final command = data['command'] as String? ?? '';
    if (!AriamiConnectCommand.supported.contains(command)) {
      _sendCommandResult(
        socket,
        commandId,
        ok: false,
        code: 'UNSUPPORTED_COMMAND',
        message: 'That playback command is not supported.',
        ownerEpoch: session?.ownerEpoch,
        activeDeviceId: session?.activeDeviceId,
      );
      return;
    }
    late final Map<String, dynamic> arguments;
    try {
      arguments = validateConnectCommandArguments(
        command,
        data['arguments'] ?? const <String, dynamic>{},
      );
    } on FormatException catch (error) {
      _sendCommandResult(
        socket,
        commandId,
        ok: false,
        code: command == AriamiConnectCommand.playContext
            ? 'PLAY_CONTEXT_TOO_LARGE'
            : 'INVALID_ARGUMENTS',
        message: error.message,
        ownerEpoch: session?.ownerEpoch,
        activeDeviceId: session?.activeDeviceId,
      );
      return;
    }
    final target = _peerForDevice(peer.userId, session?.activeDeviceId);
    if (target == null) {
      _sendCommandResult(
        socket,
        commandId,
        ok: false,
        message: 'The active playback device is offline.',
        ownerEpoch: session?.ownerEpoch,
        activeDeviceId: session?.activeDeviceId,
      );
      return;
    }
    if (!target.peer.supportedCommands.contains(command)) {
      _sendCommandResult(
        socket,
        commandId,
        ok: false,
        code: 'UNSUPPORTED_COMMAND',
        message: 'The active playback device does not support that command.',
        ownerEpoch: session?.ownerEpoch,
        activeDeviceId: session?.activeDeviceId,
      );
      return;
    }
    if (session!.pendingCommands.length >= maxPendingCommands) {
      _sendCommandResult(
        socket,
        commandId,
        ok: false,
        code: 'COMMAND_OVERFLOW',
        message: 'Too many playback commands are awaiting a result.',
        ownerEpoch: session.ownerEpoch,
        activeDeviceId: session.activeDeviceId,
      );
      return;
    }
    session.lastCommandAtByDevice[peer.deviceId] = _now();
    // A validated playback command is semantic work even before the owner has
    // time to publish its resulting state. Reserving the generation here
    // prevents a handoff prepared concurrently with pause/seek/skip/queue
    // control from committing the older snapshot.
    session.semanticGeneration++;
    final payload = immutableConnectJson(<String, dynamic>{
      'commandId': commandId,
      'command': command,
      'arguments': arguments,
      'requestedBy': peer.deviceId,
      'activeDeviceId': session.activeDeviceId,
      'ownerEpoch': session.ownerEpoch,
      'semanticGeneration': session.semanticGeneration,
    })! as Map<String, dynamic>;
    final pending = _PendingCommand(
      userId: peer.userId,
      requester: socket,
      requesterDeviceId: peer.deviceId,
      targetDeviceId: target.peer.deviceId,
      targetConnection: target.socket,
      ownerEpoch: session.ownerEpoch,
      payload: payload,
      fingerprint: jsonEncode(<String, dynamic>{
        'command': command,
        'arguments': arguments,
      }),
    );
    session.pendingCommands[commandId] = pending;
    pending.timeout = _timerFactory(commandTimeout, () {
      final timedOut = session.pendingCommands.remove(commandId);
      if (timedOut != null) {
        final result = <String, dynamic>{
          'commandId': commandId,
          'ok': false,
          'code': 'COMMAND_TIMEOUT',
          'message': 'The active playback device is not responding.',
          'ownerEpoch': timedOut.ownerEpoch,
          'activeDeviceId': session.activeDeviceId,
        };
        _rememberCommandResult(
            session, commandId, timedOut.requesterDeviceId, result);
        _send(
            timedOut.requester, AriamiConnectMessageType.commandResult, result);
      }
    });
    _deliverPendingCommand(session, commandId, pending);
  }

  void _deliverPendingCommand(
    _ConnectSession session,
    String commandId,
    _PendingCommand pending,
  ) {
    if (session.pendingCommands[commandId] != pending) return;
    if (session.ownerEpoch != pending.ownerEpoch ||
        session.activeDeviceId != pending.targetDeviceId) {
      _settlePendingCommand(
        session,
        commandId,
        pending,
        code: 'STALE_OWNER',
        message: 'Playback ownership changed before the command completed.',
      );
      return;
    }
    final target = _peerForDevice(
      pending.userId,
      pending.targetDeviceId,
    );
    if (target == null) return; // Retain until replacement or timeout.
    if (pending.deliveryAttempts >= maxCommandDeliveries) {
      _settlePendingCommand(
        session,
        commandId,
        pending,
        code: 'COMMAND_RETRY_EXHAUSTED',
        message: 'The playback command could not be delivered reliably.',
      );
      return;
    }
    pending.targetConnection = target.socket;
    pending.deliveryAttempts++;
    _send(target.socket, AriamiConnectMessageType.command, pending.payload);
  }

  void _redeliverPendingCommands(
    _ConnectSession session,
    WebSocketChannel replacement,
    _ConnectPeer peer,
  ) {
    for (final entry
        in session.pendingCommands.entries.toList(growable: false)) {
      final pending = entry.value;
      if (pending.targetDeviceId != peer.deviceId ||
          pending.ownerEpoch != session.ownerEpoch) {
        continue;
      }
      pending.targetConnection = replacement;
      _deliverPendingCommand(session, entry.key, pending);
    }
  }

  void _settlePendingCommand(
    _ConnectSession session,
    String commandId,
    _PendingCommand pending, {
    required String code,
    required String message,
  }) {
    if (session.pendingCommands.remove(commandId) != pending) return;
    pending.timeout?.cancel();
    final result = <String, dynamic>{
      'commandId': commandId,
      'ok': false,
      'code': code,
      'message': message,
      'ownerEpoch': session.ownerEpoch,
      'activeDeviceId': session.activeDeviceId,
    };
    _rememberCommandResult(
      session,
      commandId,
      pending.requesterDeviceId,
      result,
    );
    _send(pending.requester, AriamiConnectMessageType.commandResult, result);
  }

  void _handleCommandResult(_ConnectPeer peer, Map<String, dynamic> data) {
    final commandId = data['commandId'] as String?;
    if (commandId == null) return;
    final session = _sessions[peer.userId];
    final formerOwnerPause = session?.pendingFormerOwnerPauses[commandId];
    if (formerOwnerPause != null &&
        formerOwnerPause.targetDeviceId == peer.deviceId &&
        _matchesEpoch(data, formerOwnerPause.ownerEpoch)) {
      formerOwnerPause.timeout?.cancel();
      formerOwnerPause.timeout = null;
      if (data['ok'] == true) {
        session!.pendingFormerOwnerPauses.remove(commandId);
      }
      return;
    }
    final pending = session?.pendingCommands[commandId];
    if (pending != null &&
        pending.targetDeviceId == peer.deviceId &&
        _matchesEpoch(data, pending.ownerEpoch)) {
      session!.pendingCommands.remove(commandId);
      pending.timeout?.cancel();
      final result = Map<String, dynamic>.from(data)
        ..putIfAbsent('ownerEpoch', () => pending.ownerEpoch)
        ..putIfAbsent('activeDeviceId', () => session.activeDeviceId);
      _rememberCommandResult(
        session,
        commandId,
        pending.requesterDeviceId,
        result,
      );
      _send(pending.requester, AriamiConnectMessageType.commandResult, result);
    }
  }

  void _sendCommandResult(
    WebSocketChannel socket,
    String commandId, {
    required bool ok,
    String? code,
    String? message,
    int? ownerEpoch,
    String? activeDeviceId,
    bool remember = true,
  }) {
    final result = <String, dynamic>{
      'commandId': commandId,
      'ok': ok,
      if (code != null) 'code': code,
      if (message != null) 'message': message,
      if (ownerEpoch != null) 'ownerEpoch': ownerEpoch,
      if (activeDeviceId != null) 'activeDeviceId': activeDeviceId,
    };
    if (remember && commandId.isNotEmpty) {
      final requester = _peers[socket];
      final session = requester == null ? null : _sessions[requester.userId];
      if (session != null) {
        _rememberCommandResult(
          session,
          commandId,
          requester!.deviceId,
          result,
        );
      }
    }
    _send(socket, AriamiConnectMessageType.commandResult, result);
  }

  void _rememberCommandResult(
    _ConnectSession session,
    String commandId,
    String requesterDeviceId,
    Map<String, dynamic> data,
  ) {
    session.completedCommands.remove(commandId);
    session.completedCommands[commandId] = _CompletedCommand(
      requesterDeviceId: requesterDeviceId,
      result: Map<String, dynamic>.unmodifiable(data),
    );
    while (session.completedCommands.length > kMaxCompletedConnectCommands) {
      session.completedCommands.remove(session.completedCommands.keys.first);
    }
  }

  void _handleTransfer(
      WebSocketChannel socket, _ConnectPeer peer, Map<String, dynamic> data,
      {bool automatic = false, AriamiPlaybackSnapshot? automaticSnapshot}) {
    final targetId = data['targetDeviceId'] as String? ?? '';
    final target = _peerForDevice(peer.userId, targetId);
    if (target == null || !target.peer.canPlay) {
      _sendError(
          socket, 'DEVICE_OFFLINE', 'That playback device is not available.');
      return;
    }
    final session = _sessions.putIfAbsent(peer.userId, _ConnectSession.new);
    if (!_acceptEpoch(session, data)) {
      _sendError(socket, 'STALE_OWNER_EPOCH',
          'Playback ownership changed before that handoff arrived.');
      return;
    }
    if (!automatic) session.failover = null;
    final now = _now();
    final expired = session.pendingTransfers.values
        .where(
            (transfer) => now.difference(transfer.createdAt) > transferTimeout)
        .toList(growable: false);
    for (final transfer in expired) {
      _cancelTransfer(
        peer.userId,
        session,
        transfer,
        reason: 'timeout',
      );
      _sendError(transfer.requester, 'TRANSFER_TIMEOUT',
          'The target device did not respond to the handoff.');
    }
    // A newer device choice wins over an in-flight picker action.
    final superseded = session.pendingTransfers.values.toList(growable: false);
    for (final transfer in superseded) {
      _cancelTransfer(
        peer.userId,
        session,
        transfer,
        reason: 'superseded',
      );
      _sendError(transfer.requester, 'TRANSFER_SUPERSEDED',
          'A newer playback-device choice replaced this handoff.');
    }
    final snapshot = automaticSnapshot ?? session.snapshot;
    if (snapshot == null || snapshot.queue.isEmpty) {
      _sendError(socket, 'NO_SESSION',
          'There is no playback session to transfer yet.');
      return;
    }
    final transferId = '${_now().microsecondsSinceEpoch}-${peer.deviceId}';
    final preparedSnapshot = snapshot.compensated(_now());
    final pending = _PendingTransfer(
      id: transferId,
      sourceDeviceId: session.activeDeviceId,
      targetDeviceId: targetId,
      requester: socket,
      requesterDeviceId: peer.deviceId,
      snapshot: preparedSnapshot,
      createdAt: now,
      ownerEpoch: session.ownerEpoch,
      queueCounter: session.queueCounter,
      semanticGeneration: session.semanticGeneration,
      automatic: automatic,
    );
    session.pendingTransfers[transferId] = pending;
    pending.timeout = _timerFactory(transferTimeout, () {
      final timedOut = session.pendingTransfers.remove(transferId);
      if (timedOut != null) {
        _sendTransferCancellation(
          peer.userId,
          timedOut,
          reason: 'timeout',
        );
        if (timedOut.automatic) {
          _continueAutomaticFailover(peer.userId, session, timedOut);
        } else {
          _sendError(timedOut.requester, 'TRANSFER_TIMEOUT',
              'The target device did not respond to the handoff.');
        }
      }
    });
    _send(target.socket, AriamiConnectMessageType.transfer, <String, dynamic>{
      'phase': 'prepare',
      'transferId': transferId,
      'sourceDeviceId': session.activeDeviceId,
      'targetDeviceId': targetId,
      'snapshot': preparedSnapshot.toJson(
        includeBackingOrder:
            target.peer.protocolVersion >= AriamiConnectProtocol.v3,
      ),
      'queueCounter': session.queueCounter,
      'ownerEpoch': session.ownerEpoch,
      'semanticGeneration': session.semanticGeneration,
    });
  }

  void _handleTransferResult(_ConnectPeer peer, Map<String, dynamic> data) {
    final session = _sessions[peer.userId];
    final transferId = data['transferId'] as String?;
    if (session == null || transferId == null) return;
    final transfer = session.pendingTransfers[transferId];
    if (transfer == null || transfer.targetDeviceId != peer.deviceId) return;
    session.pendingTransfers.remove(transferId);
    transfer.timeout?.cancel();
    if (session.ownerEpoch != transfer.ownerEpoch ||
        !_matchesEpoch(data, transfer.ownerEpoch)) {
      _sendTransferCancellation(
        peer.userId,
        transfer,
        reason: 'stale_owner',
      );
      if (transfer.automatic) {
        session.failover = null;
      } else {
        _sendError(transfer.requester, 'STALE_OWNER_EPOCH',
            'Playback ownership changed before that handoff completed.');
      }
      return;
    }
    final requiresRevisionEcho =
        peer.protocolVersion >= AriamiConnectProtocol.v3;
    final echoedQueueCounter = (data['queueCounter'] as num?)?.toInt();
    final echoedSemanticGeneration =
        (data['semanticGeneration'] as num?)?.toInt();
    final revisionMismatch = session.queueCounter != transfer.queueCounter ||
        session.semanticGeneration != transfer.semanticGeneration ||
        (requiresRevisionEcho &&
            (echoedQueueCounter != transfer.queueCounter ||
                echoedSemanticGeneration != transfer.semanticGeneration));
    if (revisionMismatch) {
      _sendTransferCancellation(
        peer.userId,
        transfer,
        reason: 'state_changed',
      );
      if (transfer.automatic) {
        _continueAutomaticFailover(peer.userId, session, transfer);
      } else {
        _sendError(transfer.requester, 'TRANSFER_STATE_CHANGED',
            'Playback changed while that handoff was preparing.');
      }
      return;
    }
    if (data['ok'] != true) {
      _sendTransferCancellation(
        peer.userId,
        transfer,
        reason: 'rejected',
      );
      if (transfer.automatic) {
        _continueAutomaticFailover(peer.userId, session, transfer);
      } else {
        _sendError(
            transfer.requester,
            'TRANSFER_FAILED',
            data['message'] as String? ??
                'The target device could not start playback.');
      }
      return;
    }

    _commitOwnership(
      peer.userId,
      session,
      transfer.targetDeviceId,
      requestedBy: transfer.requesterDeviceId,
    );
    session.snapshot = transfer.snapshot.compensated(_now());
    session.revision++;
    for (final entry in _peers.entries) {
      if (entry.value.userId == peer.userId) {
        _send(entry.key, AriamiConnectMessageType.transfer, <String, dynamic>{
          'phase': 'commit',
          'transferId': transfer.id,
          'sourceDeviceId': transfer.sourceDeviceId,
          'targetDeviceId': transfer.targetDeviceId,
          'snapshot': session.snapshot!.toJson(
            includeBackingOrder:
                entry.value.protocolVersion >= AriamiConnectProtocol.v3,
          ),
          if (entry.value.protocolVersion >= AriamiConnectProtocol.v3)
            'queueCounter': session.queueCounter,
          if (entry.value.protocolVersion >= AriamiConnectProtocol.v3)
            'stateRevision': session.revision
          else
            'revision': session.revision,
          'ownerEpoch': session.ownerEpoch,
          'semanticGeneration': session.semanticGeneration,
        });
      }
    }
    _broadcastDevices(peer.userId);
  }

  /// Renames the sender's own device. The new name is broadcast to every
  /// Connect client of the account, and [onDeviceRenamed] lets the server
  /// persist it so it survives reconnects and restarts.
  void _handleRename(
      WebSocketChannel socket, _ConnectPeer peer, Map<String, dynamic> data) {
    final name = normalizeDeviceDisplayName(data['name'] as String?);
    if (name == null) {
      _sendError(socket, 'INVALID_NAME',
          'Device names need 1-$kMaxDeviceDisplayNameLength visible characters.');
      return;
    }
    // A device may own several sockets (library sync + Connect); keep every
    // peer for this device consistent.
    for (final other in _peers.values) {
      if (other.userId == peer.userId && other.deviceId == peer.deviceId) {
        other.deviceName = name;
      }
    }
    onDeviceRenamed?.call(peer.userId, peer.deviceId, name);
    _broadcastDevices(peer.userId);
  }

  void _sendWelcome(WebSocketChannel socket, _ConnectPeer peer) {
    final session = _sessions[peer.userId];
    // Version 2: command delivery is idempotent — the hub deduplicates
    // replayed commandIds and replays cached results, so clients may safely
    // retransmit unacknowledged commands. Clients must not retry against
    // version 1 hubs, which forward every replay to the active device.
    _send(socket, AriamiConnectMessageType.welcome, <String, dynamic>{
      'protocolVersion': peer.protocolVersion,
      'supportedCommands': _sortedCommands(peer.supportedCommands),
      'devices': _deviceJson(peer.userId),
      'activeDeviceId': session?.activeDeviceId,
      if (peer.protocolVersion < AriamiConnectProtocol.v3 &&
          session?.snapshot != null)
        'snapshot': session!.snapshot!.toJson(),
      if (peer.protocolVersion >= AriamiConnectProtocol.v3)
        'queueCounter': session?.queueCounter ?? 0,
      if (peer.protocolVersion >= AriamiConnectProtocol.v3)
        'stateRevision': session?.revision ?? 0
      else
        'revision': session?.revision ?? 0,
      'ownerEpoch': session?.ownerEpoch ?? 0,
      'semanticGeneration': session?.semanticGeneration ?? 0,
    });
    if (peer.protocolVersion >= AriamiConnectProtocol.v3 && session != null) {
      if (session.queue != null) _sendQueue(socket, session);
      if (session.snapshot != null) _sendState(socket, peer, session);
    }
  }

  int _negotiateProtocolVersion(Map<String, dynamic>? hello) {
    final offered = hello?['protocolVersions'];
    // num equality already spans int and double, so 3.0 matches without a
    // toInt() round trip that throws on the Infinity jsonDecode returns for
    // literals like 1e999.
    if (protocolV3Enabled &&
        offered is List &&
        offered.any((version) =>
            version is num && version == AriamiConnectProtocol.v3)) {
      return AriamiConnectProtocol.v3;
    }
    // A missing/malformed offer is an old peer. Preserve the hub's established
    // v2 welcome and full-snapshot semantics for that rolling-upgrade path.
    return AriamiConnectProtocol.v2;
  }

  Set<String> _readSupportedCommands(Map<String, dynamic>? hello) {
    if (hello == null || !hello.containsKey('supportedCommands')) {
      // A peer without a capability offer predates slice 6. Preserve the
      // established rolling-upgrade behaviour and let the protocol allowlist
      // describe it until that device upgrades.
      return AriamiConnectCommand.supported;
    }
    final offered = hello['supportedCommands'];
    if (offered is! List) return const <String>{};
    return Set<String>.unmodifiable(
      offered
          .whereType<String>()
          .where(AriamiConnectCommand.supported.contains),
    );
  }

  List<String> _sortedCommands(Set<String> commands) =>
      commands.toList(growable: false)..sort();

  void _broadcastDevices(String userId) {
    final payload = <String, dynamic>{
      'devices': _deviceJson(userId),
      'activeDeviceId': _sessions[userId]?.activeDeviceId,
      'ownerEpoch': _sessions[userId]?.ownerEpoch ?? 0,
      'semanticGeneration': _sessions[userId]?.semanticGeneration ?? 0,
    };
    for (final entry in _peers.entries) {
      if (entry.value.userId == userId && entry.value.canPlay) {
        _send(entry.key, AriamiConnectMessageType.devices, payload);
      }
    }
  }

  void _broadcastState(String userId, _ConnectSession session,
      {WebSocketChannel? except}) {
    for (final entry in _peers.entries) {
      if (entry.key != except && entry.value.userId == userId) {
        _sendState(entry.key, entry.value, session);
      }
    }
  }

  void _broadcastQueue(String userId, _ConnectSession session,
      {WebSocketChannel? except}) {
    for (final entry in _peers.entries) {
      if (entry.key != except &&
          entry.value.userId == userId &&
          entry.value.protocolVersion >= AriamiConnectProtocol.v3) {
        _sendQueue(entry.key, session);
      }
    }
  }

  void _sendQueue(WebSocketChannel socket, _ConnectSession session) {
    final queue = session.queue;
    if (queue == null) return;
    _send(socket, AriamiConnectMessageType.queue, <String, dynamic>{
      'activeDeviceId': session.activeDeviceId,
      'ownerEpoch': session.ownerEpoch,
      'queueCounter': session.queueCounter,
      'semanticGeneration': session.semanticGeneration,
      'tracks': queue.tracks,
      'backingOrder': queue.backingOrder,
      if (queue.sourceId != null) 'sourceId': queue.sourceId,
    });
  }

  void _sendState(
      WebSocketChannel socket, _ConnectPeer peer, _ConnectSession session) {
    final snapshot = session.snapshot;
    if (snapshot == null) return;
    if (peer.protocolVersion >= AriamiConnectProtocol.v3) {
      _send(socket, AriamiConnectMessageType.state, <String, dynamic>{
        'activeDeviceId': session.activeDeviceId,
        'ownerEpoch': session.ownerEpoch,
        'queueCounter': session.queueCounter,
        'semanticGeneration': session.semanticGeneration,
        'currentIndex': snapshot.currentIndex,
        'positionMs': snapshot.positionMs,
        'durationMs': snapshot.durationMs,
        'isPlaying': snapshot.isPlaying,
        'shuffle': snapshot.shuffle,
        'repeatMode': snapshot.repeatMode,
        'volume': snapshot.volume,
        'stateRevision': session.revision,
        'updatedAt': (snapshot.updatedAt ?? _now()).toIso8601String(),
      });
      return;
    }
    _send(socket, AriamiConnectMessageType.state, <String, dynamic>{
      'activeDeviceId': session.activeDeviceId,
      'snapshot': snapshot.toJson(),
      'revision': session.revision,
      'ownerEpoch': session.ownerEpoch,
      'semanticGeneration': session.semanticGeneration,
    });
  }

  /// Epochs are optional only for rolling compatibility with older v2 peers.
  /// Once a peer sends one, the hub accepts work solely for its current epoch;
  /// future values are invalid too because only the hub may mint them.
  bool _acceptEpoch(_ConnectSession session, Map<String, dynamic> data) {
    final raw = data['ownerEpoch'];
    if (raw == null) return true;
    if (raw is! num ||
        raw != raw.toInt() ||
        raw.toInt() != session.ownerEpoch) {
      return false;
    }
    return true;
  }

  bool _matchesEpoch(Map<String, dynamic> data, int expected) {
    final raw = data['ownerEpoch'];
    return raw == null ||
        (raw is num && raw == raw.toInt() && raw.toInt() == expected);
  }

  void _sendAuthoritativeState(
      WebSocketChannel socket, _ConnectSession session) {
    final peer = _peers[socket];
    if (peer == null || session.snapshot == null) return;
    if (peer.protocolVersion >= AriamiConnectProtocol.v3) {
      _sendQueue(socket, session);
    }
    _sendState(socket, peer, session);
  }

  void _commitOwnership(
    String userId,
    _ConnectSession session,
    String? nextDeviceId, {
    required String requestedBy,
  }) {
    final previousDeviceId = session.activeDeviceId;
    if (previousDeviceId == nextDeviceId) return;

    session.activeDeviceId = nextDeviceId;
    session.ownerEpoch++;
    session.semanticGeneration++;
    session.disconnectTimer?.cancel();
    session.disconnectTimer = null;
    session.failover = null;
    if (nextDeviceId != null) {
      _clearFormerOwnerPauses(session, nextDeviceId);
    }

    // Commands are bound to the owner that was authoritative when accepted.
    // A takeover settles them immediately instead of allowing a later result
    // from the former owner to look successful in the new epoch.
    final pendingCommands = session.pendingCommands.entries.toList();
    for (final entry in pendingCommands) {
      session.pendingCommands.remove(entry.key);
      entry.value.timeout?.cancel();
      final result = <String, dynamic>{
        'commandId': entry.key,
        'ok': false,
        'code': 'STALE_OWNER',
        'message': 'Playback ownership changed before the command completed.',
        'ownerEpoch': session.ownerEpoch,
        'activeDeviceId': session.activeDeviceId,
      };
      _rememberCommandResult(
        session,
        entry.key,
        entry.value.requesterDeviceId,
        result,
      );
      _send(entry.value.requester, AriamiConnectMessageType.commandResult,
          result);
    }

    // A prepare belongs to the epoch whose snapshot it carries. A takeover
    // invalidates it; allowing its late result to commit would resurrect an
    // owner that already lost the race.
    final pendingTransfers = session.pendingTransfers.values.toList();
    for (final transfer in pendingTransfers) {
      _cancelTransfer(
        userId,
        session,
        transfer,
        reason: 'stale_owner',
      );
      _sendError(transfer.requester, 'STALE_OWNER_EPOCH',
          'Playback ownership changed before that handoff completed.');
    }

    _refreshFormerOwnerPauses(userId, session);
    if (previousDeviceId != null) {
      _trackFormerOwnerPause(
        userId,
        session,
        previousDeviceId,
        requestedBy: requestedBy,
      );
    }
  }

  void _cancelTransfer(
    String userId,
    _ConnectSession session,
    _PendingTransfer transfer, {
    required String reason,
    bool notifyTarget = true,
  }) {
    if (session.pendingTransfers.remove(transfer.id) != transfer) return;
    transfer.timeout?.cancel();
    if (notifyTarget) {
      _sendTransferCancellation(userId, transfer, reason: reason);
    }
  }

  void _sendTransferCancellation(
    String userId,
    _PendingTransfer transfer, {
    required String reason,
  }) {
    final target = _peerForDevice(userId, transfer.targetDeviceId);
    if (target == null) return;
    _send(target.socket, AriamiConnectMessageType.transfer, <String, dynamic>{
      'phase': 'cancel',
      'transferId': transfer.id,
      'sourceDeviceId': transfer.sourceDeviceId,
      'targetDeviceId': transfer.targetDeviceId,
      'reason': reason,
      'ownerEpoch': transfer.ownerEpoch,
      'queueCounter': transfer.queueCounter,
      'semanticGeneration': transfer.semanticGeneration,
    });
  }

  void _adoptSemanticGeneration(
    _ConnectSession session,
    Map<String, dynamic> data, {
    required bool fallbackChanged,
  }) {
    final raw = data['semanticGeneration'];
    if (raw is num && raw == raw.toInt() && raw.toInt() >= 0) {
      if (raw.toInt() > session.semanticGeneration) {
        session.semanticGeneration = raw.toInt();
      }
      return;
    }
    if (fallbackChanged) session.semanticGeneration++;
  }

  bool _semanticStateChanged(
    AriamiPlaybackSnapshot? previous,
    AriamiPlaybackSnapshot next,
  ) {
    if (previous == null) return true;
    if (previous.queueFingerprint != next.queueFingerprint ||
        previous.currentIndex != next.currentIndex ||
        previous.isPlaying != next.isPlaying ||
        previous.shuffle != next.shuffle ||
        previous.repeatMode != next.repeatMode ||
        previous.volume != next.volume) {
      return true;
    }
    final elapsedMs = next.updatedAt == null || previous.updatedAt == null
        ? 0
        : next.updatedAt!.difference(previous.updatedAt!).inMilliseconds;
    final expectedPosition = previous.positionMs +
        (previous.isPlaying && elapsedMs > 0 ? elapsedMs : 0);
    return (next.positionMs - expectedPosition).abs() > 1500;
  }

  void _trackFormerOwnerPause(
    String userId,
    _ConnectSession session,
    String formerDeviceId, {
    required String requestedBy,
  }) {
    _clearFormerOwnerPauses(session, formerDeviceId);
    final commandId = 'owner-${session.ownerEpoch}-pause-$formerDeviceId';
    final pending = _PendingFormerOwnerPause(
      targetDeviceId: formerDeviceId,
      ownerEpoch: session.ownerEpoch,
      requestedBy: requestedBy,
    );
    session.pendingFormerOwnerPauses[commandId] = pending;
    _deliverFormerOwnerPause(userId, session, commandId, pending);
  }

  void _refreshFormerOwnerPauses(
    String userId,
    _ConnectSession session,
  ) {
    final stale =
        session.pendingFormerOwnerPauses.values.toList(growable: false);
    session.pendingFormerOwnerPauses.clear();
    for (final pending in stale) {
      pending.timeout?.cancel();
      if (pending.targetDeviceId == session.activeDeviceId) continue;
      final refreshed = _PendingFormerOwnerPause(
        targetDeviceId: pending.targetDeviceId,
        ownerEpoch: session.ownerEpoch,
        requestedBy: pending.requestedBy,
      );
      final commandId =
          'owner-${session.ownerEpoch}-pause-${pending.targetDeviceId}';
      session.pendingFormerOwnerPauses[commandId] = refreshed;
      _deliverFormerOwnerPause(userId, session, commandId, refreshed);
    }
  }

  void _redeliverFormerOwnerPause(
    String userId,
    _ConnectSession session,
    String deviceId,
  ) {
    final pending = session.pendingFormerOwnerPauses.entries
        .where((entry) => entry.value.targetDeviceId == deviceId)
        .toList(growable: false);
    for (final entry in pending) {
      _deliverFormerOwnerPause(userId, session, entry.key, entry.value);
    }
  }

  void _deliverFormerOwnerPause(
    String userId,
    _ConnectSession session,
    String commandId,
    _PendingFormerOwnerPause pending,
  ) {
    final former = _peerForDevice(userId, pending.targetDeviceId);
    if (former == null) return;
    pending.timeout?.cancel();
    pending.timeout = _timerFactory(commandTimeout, () {
      if (session.pendingFormerOwnerPauses[commandId] == pending) {
        pending.timeout = null;
      }
    });
    _send(former.socket, AriamiConnectMessageType.command, <String, dynamic>{
      'commandId': commandId,
      'command': AriamiConnectCommand.pause,
      'arguments': const <String, dynamic>{},
      'requestedBy': pending.requestedBy,
      'activeDeviceId': session.activeDeviceId,
      'ownerEpoch': pending.ownerEpoch,
      'semanticGeneration': session.semanticGeneration,
    });
  }

  void _clearFormerOwnerPauses(
    _ConnectSession session,
    String deviceId,
  ) {
    final stale = session.pendingFormerOwnerPauses.entries
        .where((entry) => entry.value.targetDeviceId == deviceId)
        .toList(growable: false);
    for (final entry in stale) {
      session.pendingFormerOwnerPauses.remove(entry.key);
      entry.value.timeout?.cancel();
    }
  }

  List<Map<String, dynamic>> _deviceJson(String userId) {
    final activeId = _sessions[userId]?.activeDeviceId;
    final result = _peers.values
        .where((peer) => peer.userId == userId && peer.canPlay)
        .map((peer) => <String, dynamic>{
              'id': peer.deviceId,
              'name': peer.deviceName,
              'type': peer.clientType,
              'canPlay': peer.canPlay,
              'connectedAt': peer.connectedAt.toIso8601String(),
              'isActive': peer.deviceId == activeId,
              'supportedCommands': _sortedCommands(peer.supportedCommands),
            })
        .toList(growable: false);
    result.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return result;
  }

  /// Sends [message] to every connected playback client of [userId]
  /// (optionally excluding [exceptDeviceId], typically the device that caused
  /// the update). Used for account-scoped notifications such as
  /// `listening_stats_updated`.
  void sendToUser(
    String userId,
    WsMessage message, {
    String? exceptDeviceId,
  }) {
    for (final entry in _peers.entries) {
      final peer = entry.value;
      if (peer.userId != userId) continue;
      if (exceptDeviceId != null && peer.deviceId == exceptDeviceId) continue;
      _send(entry.key, message.type, message.data ?? const <String, dynamic>{});
    }
  }

  ({WebSocketChannel socket, _ConnectPeer peer})? _peerForDevice(
      String userId, String? deviceId) {
    if (deviceId == null) return null;
    for (final entry in _peers.entries) {
      if (entry.value.userId == userId && entry.value.deviceId == deviceId) {
        return (socket: entry.key, peer: entry.value);
      }
    }
    return null;
  }

  void _sendError(WebSocketChannel socket, String code, String message) =>
      _send(socket, AriamiConnectMessageType.error,
          <String, dynamic>{'code': code, 'message': message});

  void _send(WebSocketChannel socket, String type, Map<String, dynamic> data) {
    try {
      socket.sink.add(jsonEncode(WsMessage(type: type, data: data).toJson()));
    } catch (_) {
      // Normal socket completion removes dead peers.
    }
  }
}

class _ConnectPeer {
  _ConnectPeer(
      {required this.userId,
      required this.deviceId,
      required this.deviceName,
      required this.clientType,
      required this.connectedAt,
      required this.lastSeen,
      required this.protocolVersion,
      required this.supportedCommands});
  final String userId;
  final String deviceId;
  String deviceName;
  final String clientType;
  final DateTime connectedAt;
  bool canPlay = false;
  int protocolVersion;
  Set<String> supportedCommands;
  // Not part of the wire model: server-internal liveness bookkeeping for the
  // stale-peer sweep. Never serialize this into AriamiConnectDevice/_deviceJson.
  DateTime lastSeen;
}

class _ConnectSession {
  String? activeDeviceId;
  int ownerEpoch = 0;
  final Map<String, DateTime> lastCommandAtByDevice = {};
  _ConnectQueueData? queue;
  int queueCounter = 0;
  AriamiPlaybackSnapshot? snapshot;
  int revision = 0;
  int semanticGeneration = 0;
  Timer? disconnectTimer;
  _PendingFailover? failover;
  final Map<String, _PendingCommand> pendingCommands = {};
  final Map<String, _PendingFormerOwnerPause> pendingFormerOwnerPauses = {};
  final LinkedHashMap<String, _CompletedCommand> completedCommands =
      LinkedHashMap<String, _CompletedCommand>();
  final Map<String, _PendingTransfer> pendingTransfers = {};
}

class _PendingFailover {
  _PendingFailover({
    required this.sourceDeviceId,
    required this.remainingCandidates,
  });

  final String sourceDeviceId;
  final List<_FailoverCandidate> remainingCandidates;
}

class _FailoverCandidate {
  const _FailoverCandidate({
    required this.deviceId,
    required this.connectedAt,
    required this.lastCommandAt,
  });

  final String deviceId;
  final DateTime connectedAt;
  final DateTime? lastCommandAt;
}

class _ConnectQueueData {
  _ConnectQueueData({
    required this.tracks,
    required this.backingOrder,
    required this.sourceId,
  }) : fingerprint = canonicalConnectQueueFingerprint(
          queue: tracks,
          backingOrder: backingOrder,
          sourceId: sourceId,
        );

  final List<Map<String, dynamic>> tracks;
  final List<int> backingOrder;
  final String? sourceId;
  final String fingerprint;
}

class _PendingCommand {
  _PendingCommand({
    required this.userId,
    required this.requester,
    required this.requesterDeviceId,
    required this.targetDeviceId,
    required this.targetConnection,
    required this.ownerEpoch,
    required this.payload,
    required this.fingerprint,
  });
  final String userId;
  WebSocketChannel requester;
  final String requesterDeviceId;
  final String targetDeviceId;
  WebSocketChannel targetConnection;
  final int ownerEpoch;
  final Map<String, dynamic> payload;
  final String fingerprint;
  int deliveryAttempts = 0;
  Timer? timeout;
}

class _CompletedCommand {
  const _CompletedCommand({
    required this.requesterDeviceId,
    required this.result,
  });

  final String requesterDeviceId;
  final Map<String, dynamic> result;
}

class _PendingFormerOwnerPause {
  _PendingFormerOwnerPause({
    required this.targetDeviceId,
    required this.ownerEpoch,
    required this.requestedBy,
  });
  final String targetDeviceId;
  final int ownerEpoch;
  final String requestedBy;
  Timer? timeout;
}

class _PendingTransfer {
  _PendingTransfer({
    required this.id,
    required this.sourceDeviceId,
    required this.targetDeviceId,
    required this.requester,
    required this.requesterDeviceId,
    required this.snapshot,
    required this.createdAt,
    required this.ownerEpoch,
    required this.queueCounter,
    required this.semanticGeneration,
    this.automatic = false,
  });
  final String id;
  final String? sourceDeviceId;
  final String targetDeviceId;
  final WebSocketChannel requester;
  final String requesterDeviceId;
  final AriamiPlaybackSnapshot snapshot;
  final DateTime createdAt;
  final int ownerEpoch;
  final int queueCounter;
  final int semanticGeneration;
  final bool automatic;
  Timer? timeout;
}
