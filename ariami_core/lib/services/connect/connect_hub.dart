import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:ariami_core/models/connect_models.dart';
import 'package:ariami_core/models/websocket_models.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Authenticated, in-memory rendezvous for Ariami Connect.
///
/// Playback remains owned and persisted by clients. After a server restart,
/// clients reconnect and the active device republishes its state.
class AriamiConnectHub {
  AriamiConnectHub({
    this.disconnectGracePeriod = const Duration(seconds: 3),
    this.commandTimeout = const Duration(seconds: 10),
    this.staleTimeout = const Duration(seconds: 90),
    this.sweepInterval = const Duration(seconds: 30),
  });

  /// Gives a playback client enough time to reconnect after a transient
  /// WebSocket drop before its controller takes over the session.
  final Duration disconnectGracePeriod;

  /// How long a relayed command may wait for the active device's result
  /// before the requester is told the device is unreachable. Long enough for
  /// a slow track load, short enough that tapping play on a dead device does
  /// not fail silently.
  final Duration commandTimeout;

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

  final Map<WebSocketChannel, _ConnectPeer> _peers = {};
  final Map<String, _ConnectSession> _sessions = {};
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
      connectedAt: DateTime.now().toUtc(),
      lastSeen: DateTime.now().toUtc(),
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
      final automaticTransfers = session.pendingTransfers.values
          .where((transfer) =>
              transfer.automatic && transfer.sourceDeviceId == deviceId)
          .toList(growable: false);
      for (final transfer in automaticTransfers) {
        session.pendingTransfers.remove(transfer.id);
        transfer.timeout?.cancel();
      }
    }
    // Identify is authenticated asynchronously by the server. A client may
    // have already sent connect_hello while that validation was in flight, so
    // recognized playback clients are made ready here as well.
    if (const {'desktop', 'mobile', 'tv'}.contains(clientType)) {
      peer.canPlay = true;
      _sendWelcome(socket, peer);
      _broadcastDevices(userId);
    }
  }

  void unregister(WebSocketChannel socket) {
    final peer = _peers.remove(socket);
    if (peer != null) {
      final session = _sessions[peer.userId];
      final abandoned = session?.pendingTransfers.values
              .where((transfer) => transfer.targetDeviceId == peer.deviceId)
              .toList(growable: false) ??
          const <_PendingTransfer>[];
      for (final transfer in abandoned) {
        session!.pendingTransfers.remove(transfer.id);
        transfer.timeout?.cancel();
        _sendError(transfer.requester, 'DEVICE_OFFLINE',
            'The target device disconnected during handoff.');
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
    _peers[socket]?.lastSeen = DateTime.now().toUtc();
  }

  /// Backstop for peers whose socket died without ever delivering a close
  /// event. Ordinary disconnects already go through [unregister] via the
  /// transport; this only catches the ones the transport never told us about.
  void _sweepStalePeers() {
    final now = DateTime.now().toUtc();
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
    _peers.clear();
  }

  void _scheduleDisconnectFailover(
      String userId, String sourceDeviceId, _ConnectSession session) {
    session.disconnectTimer?.cancel();
    session.disconnectTimer = Timer(disconnectGracePeriod, () {
      session.disconnectTimer = null;
      if (session.activeDeviceId != sourceDeviceId ||
          _peerForDevice(userId, sourceDeviceId) != null) {
        return;
      }

      // Prefer the device that most recently sent a remote-control command.
      // If it is unavailable, use the most recently connected playback
      // client. This keeps failover platform-neutral while avoiding an
      // arbitrary stale local queue.
      var target = _peerForDevice(userId, session.lastControllerDeviceId);
      if (target == null ||
          !target.peer.canPlay ||
          target.peer.deviceId == sourceDeviceId) {
        final candidates = _peers.entries
            .where((entry) =>
                entry.value.userId == userId &&
                entry.value.canPlay &&
                entry.value.deviceId != sourceDeviceId)
            .toList(growable: false)
          ..sort((a, b) => b.value.connectedAt.compareTo(a.value.connectedAt));
        if (candidates.isNotEmpty) {
          final candidate = candidates.first;
          target = (socket: candidate.key, peer: candidate.value);
        }
      }

      if (target == null) {
        _broadcastDevices(userId);
        return;
      }
      _handleTransfer(
        target.socket,
        target.peer,
        <String, dynamic>{
          'targetDeviceId': target.peer.deviceId,
          'ownerEpoch': session.ownerEpoch,
        },
        automatic: true,
      );
    });
  }

  bool handle(WebSocketChannel socket, WsMessage message) {
    // Any traffic on this socket proves it is alive, regardless of the
    // message type or whether it turns out to be one Connect handles.
    touch(socket);
    final peer = _peers[socket];
    if (peer == null || !message.type.startsWith('connect_')) return false;
    final data = message.data ?? const <String, dynamic>{};
    switch (message.type) {
      case AriamiConnectMessageType.hello:
        peer.canPlay = data['canPlay'] as bool? ?? true;
        _sendWelcome(socket, peer);
        _broadcastDevices(peer.userId);
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
    try {
      final raw = data['snapshot'];
      if (raw is! Map) throw const FormatException('Missing snapshot');
      final snapshot = AriamiPlaybackSnapshot.fromJson(
        Map<String, dynamic>.from(raw),
      ).copyWith(updatedAt: DateTime.now().toUtc());
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
      session.snapshot = snapshot;
      session.revision++;
      _broadcastState(peer.userId, session, except: socket);
      if (activate && previousActive != session.activeDeviceId) {
        _broadcastDevices(peer.userId);
      }
    } on FormatException catch (error) {
      _sendError(socket, 'INVALID_STATE', error.message);
    }
  }

  void _handleCommand(
      WebSocketChannel socket, _ConnectPeer peer, Map<String, dynamic> data) {
    final commandId = data['commandId'] as String? ??
        '${DateTime.now().microsecondsSinceEpoch}-${peer.deviceId}';
    final command = data['command'] as String? ?? '';
    final session = _sessions[peer.userId];
    if (!AriamiConnectCommand.supported.contains(command)) {
      _sendCommandResult(
        socket,
        commandId,
        ok: false,
        message: 'That playback command is not supported.',
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
        message: 'Playback ownership changed before that command arrived.',
        ownerEpoch: session.ownerEpoch,
        activeDeviceId: session.activeDeviceId,
      );
      return;
    }
    final completed = session?.completedCommands[commandId];
    if (completed != null) {
      _send(socket, AriamiConnectMessageType.commandResult, completed);
      return;
    }
    final existing = session?.pendingCommands[commandId];
    if (existing != null) {
      // A controller can reconnect and replay before the active device answers.
      // Move the eventual acknowledgement to its newest socket without running
      // the playback action twice.
      existing.requester = socket;
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
    if (peer.deviceId != session!.activeDeviceId) {
      session.lastControllerDeviceId = peer.deviceId;
    }
    final pending = _PendingCommand(
      requester: socket,
      targetDeviceId: target.peer.deviceId,
      ownerEpoch: session.ownerEpoch,
    );
    session.pendingCommands[commandId] = pending;
    pending.timeout = Timer(commandTimeout, () {
      final timedOut = session.pendingCommands.remove(commandId);
      if (timedOut != null) {
        final result = <String, dynamic>{
          'commandId': commandId,
          'ok': false,
          'message': 'The active playback device is not responding.',
          'ownerEpoch': timedOut.ownerEpoch,
          'activeDeviceId': session.activeDeviceId,
        };
        _rememberCommandResult(session, commandId, result);
        _send(
            timedOut.requester, AriamiConnectMessageType.commandResult, result);
      }
    });
    _send(target.socket, AriamiConnectMessageType.command, <String, dynamic>{
      'commandId': commandId,
      'command': command,
      'arguments': data['arguments'] is Map
          ? Map<String, dynamic>.from(data['arguments'] as Map)
          : const <String, dynamic>{},
      'requestedBy': peer.deviceId,
      'activeDeviceId': session.activeDeviceId,
      'ownerEpoch': session.ownerEpoch,
    });
  }

  void _handleCommandResult(_ConnectPeer peer, Map<String, dynamic> data) {
    final commandId = data['commandId'] as String?;
    if (commandId == null) return;
    final session = _sessions[peer.userId];
    final formerOwnerPause = session?.pendingFormerOwnerPauses[commandId];
    if (formerOwnerPause != null &&
        formerOwnerPause.targetDeviceId == peer.deviceId &&
        _matchesEpoch(data, formerOwnerPause.ownerEpoch)) {
      session!.pendingFormerOwnerPauses.remove(commandId);
      formerOwnerPause.timeout?.cancel();
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
      _rememberCommandResult(session, commandId, result);
      _send(pending.requester, AriamiConnectMessageType.commandResult, result);
    }
  }

  void _sendCommandResult(
    WebSocketChannel socket,
    String commandId, {
    required bool ok,
    String? message,
    int? ownerEpoch,
    String? activeDeviceId,
  }) {
    _send(socket, AriamiConnectMessageType.commandResult, <String, dynamic>{
      'commandId': commandId,
      'ok': ok,
      if (message != null) 'message': message,
      if (ownerEpoch != null) 'ownerEpoch': ownerEpoch,
      if (activeDeviceId != null) 'activeDeviceId': activeDeviceId,
    });
  }

  void _rememberCommandResult(
    _ConnectSession session,
    String commandId,
    Map<String, dynamic> data,
  ) {
    session.completedCommands.remove(commandId);
    session.completedCommands[commandId] = Map<String, dynamic>.from(data);
    while (session.completedCommands.length > 256) {
      session.completedCommands.remove(session.completedCommands.keys.first);
    }
  }

  void _handleTransfer(
      WebSocketChannel socket, _ConnectPeer peer, Map<String, dynamic> data,
      {bool automatic = false}) {
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
    if (!automatic && peer.deviceId != targetId) {
      session.lastControllerDeviceId = peer.deviceId;
    }
    final now = DateTime.now().toUtc();
    final expired = session.pendingTransfers.values
        .where((transfer) =>
            now.difference(transfer.createdAt) > const Duration(seconds: 30))
        .toList(growable: false);
    for (final transfer in expired) {
      session.pendingTransfers.remove(transfer.id);
      transfer.timeout?.cancel();
      _sendError(transfer.requester, 'TRANSFER_TIMEOUT',
          'The target device did not respond to the handoff.');
    }
    // A newer device choice wins over an in-flight picker action.
    final superseded = session.pendingTransfers.values.toList(growable: false);
    for (final transfer in superseded) {
      session.pendingTransfers.remove(transfer.id);
      transfer.timeout?.cancel();
      _sendError(transfer.requester, 'TRANSFER_SUPERSEDED',
          'A newer playback-device choice replaced this handoff.');
    }
    final snapshot = session.snapshot;
    if (snapshot == null || snapshot.queue.isEmpty) {
      _sendError(socket, 'NO_SESSION',
          'There is no playback session to transfer yet.');
      return;
    }
    final transferId =
        '${DateTime.now().microsecondsSinceEpoch}-${peer.deviceId}';
    final preparedSnapshot = snapshot.compensated(DateTime.now().toUtc());
    final pending = _PendingTransfer(
      id: transferId,
      sourceDeviceId: session.activeDeviceId,
      targetDeviceId: targetId,
      requester: socket,
      requesterDeviceId: peer.deviceId,
      snapshot: preparedSnapshot,
      createdAt: now,
      ownerEpoch: session.ownerEpoch,
      automatic: automatic,
    );
    session.pendingTransfers[transferId] = pending;
    pending.timeout = Timer(const Duration(seconds: 30), () {
      final timedOut = session.pendingTransfers.remove(transferId);
      if (timedOut != null) {
        _sendError(timedOut.requester, 'TRANSFER_TIMEOUT',
            'The target device did not respond to the handoff.');
      }
    });
    _send(target.socket, AriamiConnectMessageType.transfer, <String, dynamic>{
      'phase': 'prepare',
      'transferId': transferId,
      'sourceDeviceId': session.activeDeviceId,
      'targetDeviceId': targetId,
      'snapshot': preparedSnapshot.toJson(),
      'ownerEpoch': session.ownerEpoch,
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
      _sendError(transfer.requester, 'STALE_OWNER_EPOCH',
          'Playback ownership changed before that handoff completed.');
      return;
    }
    if (data['ok'] != true) {
      _sendError(
          transfer.requester,
          'TRANSFER_FAILED',
          data['message'] as String? ??
              'The target device could not start playback.');
      return;
    }

    _commitOwnership(
      peer.userId,
      session,
      transfer.targetDeviceId,
      requestedBy: transfer.requesterDeviceId,
    );
    session.snapshot = transfer.snapshot.compensated(DateTime.now().toUtc());
    session.revision++;
    final payload = <String, dynamic>{
      'phase': 'commit',
      'transferId': transfer.id,
      'sourceDeviceId': transfer.sourceDeviceId,
      'targetDeviceId': transfer.targetDeviceId,
      'snapshot': session.snapshot!.toJson(),
      'revision': session.revision,
      'ownerEpoch': session.ownerEpoch,
    };
    for (final entry in _peers.entries) {
      if (entry.value.userId == peer.userId) {
        _send(entry.key, AriamiConnectMessageType.transfer, payload);
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
      'protocolVersion': 2,
      'devices': _deviceJson(peer.userId),
      'activeDeviceId': session?.activeDeviceId,
      if (session?.snapshot != null) 'snapshot': session!.snapshot!.toJson(),
      'revision': session?.revision ?? 0,
      'ownerEpoch': session?.ownerEpoch ?? 0,
    });
  }

  void _broadcastDevices(String userId) {
    final payload = <String, dynamic>{
      'devices': _deviceJson(userId),
      'activeDeviceId': _sessions[userId]?.activeDeviceId,
      'ownerEpoch': _sessions[userId]?.ownerEpoch ?? 0,
    };
    for (final entry in _peers.entries) {
      if (entry.value.userId == userId && entry.value.canPlay) {
        _send(entry.key, AriamiConnectMessageType.devices, payload);
      }
    }
  }

  void _broadcastState(String userId, _ConnectSession session,
      {WebSocketChannel? except}) {
    final snapshot = session.snapshot;
    if (snapshot == null) return;
    final payload = <String, dynamic>{
      'activeDeviceId': session.activeDeviceId,
      'snapshot': snapshot.toJson(),
      'revision': session.revision,
      'ownerEpoch': session.ownerEpoch,
    };
    for (final entry in _peers.entries) {
      if (entry.key != except && entry.value.userId == userId) {
        _send(entry.key, AriamiConnectMessageType.state, payload);
      }
    }
  }

  /// Epochs are optional only for rolling compatibility with older v2 peers.
  /// Once a peer sends one, the hub accepts work solely for its current epoch;
  /// future values are invalid too because only the hub may mint them.
  bool _acceptEpoch(_ConnectSession session, Map<String, dynamic> data) {
    final raw = data['ownerEpoch'];
    if (raw == null) return true;
    if (raw is! num || raw != raw.toInt() || raw.toInt() != session.ownerEpoch) {
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
    final snapshot = session.snapshot;
    if (snapshot == null) return;
    _send(socket, AriamiConnectMessageType.state, <String, dynamic>{
      'activeDeviceId': session.activeDeviceId,
      'snapshot': snapshot.toJson(),
      'revision': session.revision,
      'ownerEpoch': session.ownerEpoch,
    });
  }

  void _commitOwnership(
    String userId,
    _ConnectSession session,
    String nextDeviceId, {
    required String requestedBy,
  }) {
    final previousDeviceId = session.activeDeviceId;
    if (previousDeviceId == nextDeviceId) return;

    session.activeDeviceId = nextDeviceId;
    session.ownerEpoch++;
    session.disconnectTimer?.cancel();
    session.disconnectTimer = null;

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
        'message': 'Playback ownership changed before the command completed.',
        'ownerEpoch': session.ownerEpoch,
        'activeDeviceId': session.activeDeviceId,
      };
      _rememberCommandResult(session, entry.key, result);
      _send(entry.value.requester, AriamiConnectMessageType.commandResult,
          result);
    }

    // A prepare belongs to the epoch whose snapshot it carries. A takeover
    // invalidates it; allowing its late result to commit would resurrect an
    // owner that already lost the race.
    final pendingTransfers = session.pendingTransfers.values.toList();
    for (final transfer in pendingTransfers) {
      session.pendingTransfers.remove(transfer.id);
      transfer.timeout?.cancel();
      _sendError(transfer.requester, 'STALE_OWNER_EPOCH',
          'Playback ownership changed before that handoff completed.');
    }

    if (previousDeviceId != null) {
      _trackFormerOwnerPause(
        userId,
        session,
        previousDeviceId,
        requestedBy: requestedBy,
      );
    }
  }

  void _trackFormerOwnerPause(
    String userId,
    _ConnectSession session,
    String formerDeviceId, {
    required String requestedBy,
  }) {
    final former = _peerForDevice(userId, formerDeviceId);
    if (former == null) return;
    final commandId = 'owner-${session.ownerEpoch}-pause-$formerDeviceId';
    final pending = _PendingFormerOwnerPause(
      targetDeviceId: formerDeviceId,
      ownerEpoch: session.ownerEpoch,
    );
    session.pendingFormerOwnerPauses[commandId] = pending;
    pending.timeout = Timer(commandTimeout, () {
      session.pendingFormerOwnerPauses.remove(commandId);
    });
    _send(former.socket, AriamiConnectMessageType.command, <String, dynamic>{
      'commandId': commandId,
      'command': AriamiConnectCommand.pause,
      'arguments': const <String, dynamic>{},
      'requestedBy': requestedBy,
      'activeDeviceId': session.activeDeviceId,
      'ownerEpoch': session.ownerEpoch,
    });
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
      required this.lastSeen});
  final String userId;
  final String deviceId;
  String deviceName;
  final String clientType;
  final DateTime connectedAt;
  bool canPlay = false;
  // Not part of the wire model: server-internal liveness bookkeeping for the
  // stale-peer sweep. Never serialize this into AriamiConnectDevice/_deviceJson.
  DateTime lastSeen;
}

class _ConnectSession {
  String? activeDeviceId;
  int ownerEpoch = 0;
  String? lastControllerDeviceId;
  AriamiPlaybackSnapshot? snapshot;
  int revision = 0;
  Timer? disconnectTimer;
  final Map<String, _PendingCommand> pendingCommands = {};
  final Map<String, _PendingFormerOwnerPause> pendingFormerOwnerPauses = {};
  final LinkedHashMap<String, Map<String, dynamic>> completedCommands =
      LinkedHashMap<String, Map<String, dynamic>>();
  final Map<String, _PendingTransfer> pendingTransfers = {};
}

class _PendingCommand {
  _PendingCommand({
    required this.requester,
    required this.targetDeviceId,
    required this.ownerEpoch,
  });
  WebSocketChannel requester;
  final String targetDeviceId;
  final int ownerEpoch;
  Timer? timeout;
}

class _PendingFormerOwnerPause {
  _PendingFormerOwnerPause({
    required this.targetDeviceId,
    required this.ownerEpoch,
  });
  final String targetDeviceId;
  final int ownerEpoch;
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
  final bool automatic;
  Timer? timeout;
}
