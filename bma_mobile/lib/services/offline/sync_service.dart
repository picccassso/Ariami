import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/connection_service.dart';

/// Types of sync actions that can be queued
enum SyncActionType {
  playlistCreate,
  playlistDelete,
  playlistAddSong,
  playlistRemoveSong,
  playlistRename,
  playCountUpdate,
}

/// Represents a sync action queued while offline
class SyncAction {
  final String id;
  final SyncActionType type;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  bool processed;

  SyncAction({
    required this.id,
    required this.type,
    required this.data,
    required this.timestamp,
    this.processed = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.index,
        'data': data,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'processed': processed,
      };

  factory SyncAction.fromJson(Map<String, dynamic> json) => SyncAction(
        id: json['id'] as String,
        type: SyncActionType.values[json['type'] as int],
        data: Map<String, dynamic>.from(json['data'] as Map),
        timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
        processed: json['processed'] as bool? ?? false,
      );
}

/// Service for managing offline sync queue
class SyncService {
  // Singleton pattern
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  static const String _syncQueueKey = 'sync_queue';

  final ConnectionService _connectionService = ConnectionService();
  final List<SyncAction> _pendingActions = [];

  StreamSubscription<bool>? _connectionSubscription;

  // Stream controller for sync status updates
  final StreamController<SyncStatus> _syncStatusController =
      StreamController<SyncStatus>.broadcast();

  /// Stream of sync status updates
  Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;

  /// Get pending actions count
  int get pendingActionsCount => _pendingActions.where((a) => !a.processed).length;

  /// Check if there are pending actions
  bool get hasPendingActions => pendingActionsCount > 0;

  // ============================================================================
  // INITIALIZATION
  // ============================================================================

  /// Initialize the sync service
  Future<void> initialize() async {
    // Load pending actions from storage
    await _loadPendingActions();

    // Listen for reconnection to process queue
    _connectionSubscription = _connectionService.connectionStateStream.listen((isConnected) {
      if (isConnected && hasPendingActions) {
        print('[SyncService] Connection restored - processing sync queue');
        processSyncQueue();
      }
    });

    print('[SyncService] Initialized - $pendingActionsCount pending actions');
  }

  /// Load pending actions from storage
  Future<void> _loadPendingActions() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_syncQueueKey) ?? [];

    _pendingActions.clear();
    for (final json in jsonList) {
      try {
        final action = SyncAction.fromJson(jsonDecode(json) as Map<String, dynamic>);
        if (!action.processed) {
          _pendingActions.add(action);
        }
      } catch (e) {
        print('[SyncService] Error parsing action: $e');
      }
    }
  }

  /// Save pending actions to storage
  Future<void> _savePendingActions() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _pendingActions
        .where((a) => !a.processed)
        .map((a) => jsonEncode(a.toJson()))
        .toList();
    await prefs.setStringList(_syncQueueKey, jsonList);
  }

  // ============================================================================
  // QUEUE MANAGEMENT
  // ============================================================================

  /// Queue an action for sync when reconnected
  Future<void> queueAction(SyncActionType type, Map<String, dynamic> data) async {
    final action = SyncAction(
      id: 'sync_${DateTime.now().millisecondsSinceEpoch}',
      type: type,
      data: data,
      timestamp: DateTime.now(),
    );

    _pendingActions.add(action);
    await _savePendingActions();

    _syncStatusController.add(SyncStatus(
      pending: pendingActionsCount,
      lastQueued: action,
    ));

    print('[SyncService] Action queued: ${type.name} - $pendingActionsCount pending');
  }

  /// Queue a playlist creation
  Future<void> queuePlaylistCreate(String playlistId, String name) async {
    await queueAction(SyncActionType.playlistCreate, {
      'playlistId': playlistId,
      'name': name,
    });
  }

  /// Queue a playlist deletion
  Future<void> queuePlaylistDelete(String playlistId) async {
    await queueAction(SyncActionType.playlistDelete, {
      'playlistId': playlistId,
    });
  }

  /// Queue adding a song to playlist
  Future<void> queuePlaylistAddSong(String playlistId, String songId) async {
    await queueAction(SyncActionType.playlistAddSong, {
      'playlistId': playlistId,
      'songId': songId,
    });
  }

  /// Queue removing a song from playlist
  Future<void> queuePlaylistRemoveSong(String playlistId, String songId) async {
    await queueAction(SyncActionType.playlistRemoveSong, {
      'playlistId': playlistId,
      'songId': songId,
    });
  }

  /// Queue a play count update
  Future<void> queuePlayCountUpdate(String songId, int playCount) async {
    await queueAction(SyncActionType.playCountUpdate, {
      'songId': songId,
      'playCount': playCount,
    });
  }

  // ============================================================================
  // SYNC PROCESSING
  // ============================================================================

  /// Process all pending sync actions
  Future<void> processSyncQueue() async {
    if (!_connectionService.isConnected) {
      print('[SyncService] Cannot sync - not connected');
      return;
    }

    if (!hasPendingActions) {
      print('[SyncService] No pending actions to sync');
      return;
    }

    print('[SyncService] Processing $pendingActionsCount pending actions...');

    _syncStatusController.add(SyncStatus(
      pending: pendingActionsCount,
      isSyncing: true,
    ));

    int successCount = 0;
    int failCount = 0;

    for (final action in _pendingActions.where((a) => !a.processed).toList()) {
      try {
        await _processAction(action);
        action.processed = true;
        successCount++;
      } catch (e) {
        print('[SyncService] Failed to process action ${action.id}: $e');
        failCount++;
      }
    }

    // Save updated state
    await _savePendingActions();

    // Remove processed actions from memory
    _pendingActions.removeWhere((a) => a.processed);

    _syncStatusController.add(SyncStatus(
      pending: pendingActionsCount,
      isSyncing: false,
      lastSyncSuccess: successCount,
      lastSyncFailed: failCount,
    ));

    print('[SyncService] Sync complete - $successCount success, $failCount failed');
  }

  /// Process a single sync action
  Future<void> _processAction(SyncAction action) async {
    // Note: These would normally call the API to sync with server
    // For now, we just mark them as processed since playlists are local-only
    
    switch (action.type) {
      case SyncActionType.playlistCreate:
        print('[SyncService] Synced playlist create: ${action.data['name']}');
        break;
      case SyncActionType.playlistDelete:
        print('[SyncService] Synced playlist delete: ${action.data['playlistId']}');
        break;
      case SyncActionType.playlistAddSong:
        print('[SyncService] Synced add song to playlist');
        break;
      case SyncActionType.playlistRemoveSong:
        print('[SyncService] Synced remove song from playlist');
        break;
      case SyncActionType.playlistRename:
        print('[SyncService] Synced playlist rename');
        break;
      case SyncActionType.playCountUpdate:
        print('[SyncService] Synced play count update');
        break;
    }

    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 100));
  }

  /// Clear all pending actions
  Future<void> clearPendingActions() async {
    _pendingActions.clear();
    await _savePendingActions();

    _syncStatusController.add(SyncStatus(pending: 0));
    print('[SyncService] All pending actions cleared');
  }

  // ============================================================================
  // CLEANUP
  // ============================================================================

  /// Dispose resources
  void dispose() {
    _connectionSubscription?.cancel();
    _syncStatusController.close();
  }
}

/// Sync status information
class SyncStatus {
  final int pending;
  final bool isSyncing;
  final SyncAction? lastQueued;
  final int lastSyncSuccess;
  final int lastSyncFailed;

  SyncStatus({
    required this.pending,
    this.isSyncing = false,
    this.lastQueued,
    this.lastSyncSuccess = 0,
    this.lastSyncFailed = 0,
  });
}




