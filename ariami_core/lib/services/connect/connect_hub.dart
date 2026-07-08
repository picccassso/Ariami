import 'dart:async';
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
  });

  /// Gives a playback client enough time to reconnect after a transient
  /// WebSocket drop before its controller takes over the session.
  final Duration disconnectGracePeriod;

  /// How long a relayed command may wait for the active device's result
  /// before the requester is told the device is unreachable. Long enough for
  /// a slow track load, short enough that tapping play on a dead device does
  /// not fail silently.
  final Duration commandTimeout;

  final Map<WebSocketChannel, _ConnectPeer> _peers = {};
  final Map<String, _ConnectSession> _sessions = {};

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
    );
    _peers[socket] = peer;
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
        <String, dynamic>{'targetDeviceId': target.peer.deviceId},
        automatic: true,
      );
    });
  }

  bool handle(WebSocketChannel socket, WsMessage message) {
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
      final previousActive = session.activeDeviceId;
      if (session.activeDeviceId == null || activate) {
        session.activeDeviceId = peer.deviceId;
      }
      // Inactive devices cannot overwrite the session being remotely
      // controlled. Answer with the authoritative state instead of dropping
      // silently, so a device that wrongly believes it is active resyncs
      // within one publish cycle instead of diverging forever.
      if (session.activeDeviceId != peer.deviceId) {
        if (session.snapshot != null) {
          _send(socket, AriamiConnectMessageType.state, <String, dynamic>{
            'activeDeviceId': session.activeDeviceId,
            'snapshot': session.snapshot!.toJson(),
            'revision': session.revision,
          });
        }
        return;
      }
      session.snapshot = snapshot;
      session.revision++;
      if (activate &&
          previousActive != null &&
          previousActive != peer.deviceId) {
        final previous = _peerForDevice(peer.userId, previousActive);
        if (previous != null) {
          _send(previous.socket,
              AriamiConnectMessageType.command, <String, dynamic>{
            'commandId': 'takeover-${DateTime.now().microsecondsSinceEpoch}',
            'command': AriamiConnectCommand.pause,
            'arguments': const <String, dynamic>{},
            'requestedBy': peer.deviceId,
          });
        }
      }
      _broadcastState(peer.userId, session, except: socket);
      if (activate) _broadcastDevices(peer.userId);
    } on FormatException catch (error) {
      _sendError(socket, 'INVALID_STATE', error.message);
    }
  }

  void _handleCommand(
      WebSocketChannel socket, _ConnectPeer peer, Map<String, dynamic> data) {
    final command = data['command'] as String? ?? '';
    if (!AriamiConnectCommand.supported.contains(command)) {
      _sendError(
          socket, 'INVALID_COMMAND', 'That playback command is not supported.');
      return;
    }
    final session = _sessions[peer.userId];
    final target = _peerForDevice(peer.userId, session?.activeDeviceId);
    if (target == null) {
      _sendError(
          socket, 'DEVICE_OFFLINE', 'The active playback device is offline.');
      return;
    }
    final commandId = data['commandId'] as String? ??
        '${DateTime.now().microsecondsSinceEpoch}-${peer.deviceId}';
    if (peer.deviceId != session!.activeDeviceId) {
      session.lastControllerDeviceId = peer.deviceId;
    }
    final pending = _PendingCommand(requester: socket);
    session.pendingCommands[commandId] = pending;
    pending.timeout = Timer(commandTimeout, () {
      final timedOut = session.pendingCommands.remove(commandId);
      if (timedOut != null) {
        _sendError(timedOut.requester, 'DEVICE_OFFLINE',
            'The active playback device is not responding.');
      }
    });
    _send(target.socket, AriamiConnectMessageType.command, <String, dynamic>{
      'commandId': commandId,
      'command': command,
      'arguments': data['arguments'] is Map
          ? Map<String, dynamic>.from(data['arguments'] as Map)
          : const <String, dynamic>{},
      'requestedBy': peer.deviceId,
    });
  }

  void _handleCommandResult(_ConnectPeer peer, Map<String, dynamic> data) {
    final commandId = data['commandId'] as String?;
    if (commandId == null) return;
    final pending = _sessions[peer.userId]?.pendingCommands.remove(commandId);
    if (pending != null) {
      pending.timeout?.cancel();
      _send(pending.requester, AriamiConnectMessageType.commandResult, data);
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
      snapshot: preparedSnapshot,
      createdAt: now,
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
    });
  }

  void _handleTransferResult(_ConnectPeer peer, Map<String, dynamic> data) {
    final session = _sessions[peer.userId];
    final transferId = data['transferId'] as String?;
    if (session == null || transferId == null) return;
    final transfer = session.pendingTransfers.remove(transferId);
    if (transfer == null || transfer.targetDeviceId != peer.deviceId) return;
    transfer.timeout?.cancel();
    if (data['ok'] != true) {
      _sendError(
          transfer.requester,
          'TRANSFER_FAILED',
          data['message'] as String? ??
              'The target device could not start playback.');
      return;
    }

    session.activeDeviceId = transfer.targetDeviceId;
    session.snapshot = transfer.snapshot.compensated(DateTime.now().toUtc());
    session.revision++;
    final payload = <String, dynamic>{
      'phase': 'commit',
      'transferId': transfer.id,
      'sourceDeviceId': transfer.sourceDeviceId,
      'targetDeviceId': transfer.targetDeviceId,
      'snapshot': session.snapshot!.toJson(),
      'revision': session.revision,
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
    _send(socket, AriamiConnectMessageType.welcome, <String, dynamic>{
      'protocolVersion': 1,
      'devices': _deviceJson(peer.userId),
      'activeDeviceId': session?.activeDeviceId,
      if (session?.snapshot != null) 'snapshot': session!.snapshot!.toJson(),
      'revision': session?.revision ?? 0,
    });
  }

  void _broadcastDevices(String userId) {
    final payload = <String, dynamic>{
      'devices': _deviceJson(userId),
      'activeDeviceId': _sessions[userId]?.activeDeviceId,
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
    };
    for (final entry in _peers.entries) {
      if (entry.key != except && entry.value.userId == userId) {
        _send(entry.key, AriamiConnectMessageType.state, payload);
      }
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
      required this.connectedAt});
  final String userId;
  final String deviceId;
  String deviceName;
  final String clientType;
  final DateTime connectedAt;
  bool canPlay = false;
}

class _ConnectSession {
  String? activeDeviceId;
  String? lastControllerDeviceId;
  AriamiPlaybackSnapshot? snapshot;
  int revision = 0;
  Timer? disconnectTimer;
  final Map<String, _PendingCommand> pendingCommands = {};
  final Map<String, _PendingTransfer> pendingTransfers = {};
}

class _PendingCommand {
  _PendingCommand({required this.requester});
  final WebSocketChannel requester;
  Timer? timeout;
}

class _PendingTransfer {
  _PendingTransfer({
    required this.id,
    required this.sourceDeviceId,
    required this.targetDeviceId,
    required this.requester,
    required this.snapshot,
    required this.createdAt,
    this.automatic = false,
  });
  final String id;
  final String? sourceDeviceId;
  final String targetDeviceId;
  final WebSocketChannel requester;
  final AriamiPlaybackSnapshot snapshot;
  final DateTime createdAt;
  final bool automatic;
  Timer? timeout;
}
