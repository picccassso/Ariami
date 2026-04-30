import 'package:flutter/services.dart';

enum NativeDownloadState {
  unavailable,
  enqueued,
  running,
  paused,
  completed,
  failed,
  cancelled,
}

class NativeDownloadStartResult {
  const NativeDownloadStartResult({
    required this.backend,
    required this.nativeTaskId,
  });

  final String backend;
  final String nativeTaskId;
}

class NativeDownloadSnapshot {
  const NativeDownloadSnapshot({
    required this.state,
    this.bytesDownloaded = 0,
    this.totalBytes = 0,
    this.errorMessage,
  });

  final NativeDownloadState state;
  final int bytesDownloaded;
  final int totalBytes;
  final String? errorMessage;

  bool get isTerminal =>
      state == NativeDownloadState.completed ||
      state == NativeDownloadState.failed ||
      state == NativeDownloadState.cancelled ||
      state == NativeDownloadState.unavailable;
}

class NativeDownloadService {
  factory NativeDownloadService() => _instance;
  NativeDownloadService._();

  static final NativeDownloadService _instance = NativeDownloadService._();
  static const MethodChannel _channel =
      MethodChannel('ariami/native_downloads');

  bool? _available;

  Future<bool> isAvailable() async {
    final cached = _available;
    if (cached != null) return cached;

    try {
      _available = await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      _available = false;
    } on PlatformException {
      _available = false;
    }
    return _available!;
  }

  Future<NativeDownloadStartResult?> startDownload({
    required String taskId,
    required String url,
    required String destinationPath,
    required String title,
    required int totalBytes,
  }) async {
    if (!await isAvailable()) return null;

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'startDownload',
        <String, dynamic>{
          'taskId': taskId,
          'url': url,
          'destinationPath': destinationPath,
          'title': title,
          'totalBytes': totalBytes,
        },
      );
      if (result == null) return null;
      final backend = result['backend'] as String?;
      final nativeTaskId = result['nativeTaskId'] as String?;
      if (backend == null || nativeTaskId == null) return null;
      return NativeDownloadStartResult(
        backend: backend,
        nativeTaskId: nativeTaskId,
      );
    } on PlatformException {
      return null;
    }
  }

  Future<NativeDownloadSnapshot> queryDownload({
    required String taskId,
    required String nativeTaskId,
  }) async {
    if (!await isAvailable()) {
      return const NativeDownloadSnapshot(
          state: NativeDownloadState.unavailable);
    }

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'queryDownload',
        <String, dynamic>{
          'taskId': taskId,
          'nativeTaskId': nativeTaskId,
        },
      );
      return _snapshotFromMap(result);
    } on PlatformException catch (e) {
      return NativeDownloadSnapshot(
        state: NativeDownloadState.failed,
        errorMessage: e.message,
      );
    }
  }

  Future<void> cancelDownload({
    required String taskId,
    required String nativeTaskId,
  }) async {
    if (!await isAvailable()) return;

    try {
      await _channel.invokeMethod<void>(
        'cancelDownload',
        <String, dynamic>{
          'taskId': taskId,
          'nativeTaskId': nativeTaskId,
        },
      );
    } on PlatformException {
      // Existing Dart cancellation remains the source of truth.
    }
  }

  NativeDownloadSnapshot _snapshotFromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return const NativeDownloadSnapshot(
          state: NativeDownloadState.unavailable);
    }

    return NativeDownloadSnapshot(
      state: _stateFromString(map['state'] as String?),
      bytesDownloaded: (map['bytesDownloaded'] as num?)?.toInt() ?? 0,
      totalBytes: (map['totalBytes'] as num?)?.toInt() ?? 0,
      errorMessage: map['errorMessage'] as String?,
    );
  }

  NativeDownloadState _stateFromString(String? state) {
    switch (state) {
      case 'enqueued':
        return NativeDownloadState.enqueued;
      case 'running':
        return NativeDownloadState.running;
      case 'paused':
        return NativeDownloadState.paused;
      case 'completed':
        return NativeDownloadState.completed;
      case 'failed':
        return NativeDownloadState.failed;
      case 'cancelled':
        return NativeDownloadState.cancelled;
      default:
        return NativeDownloadState.unavailable;
    }
  }
}
