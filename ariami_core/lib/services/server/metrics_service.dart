import 'dart:async';
import 'dart:collection';
import 'dart:convert';

/// Aggregates server-side metrics and emits periodic structured summary logs.
class AriamiMetricsService {
  AriamiMetricsService({
    this.summaryInterval = const Duration(seconds: 60),
  });

  final Duration summaryInterval;
  final Map<String, _EndpointMetricsWindow> _endpoints =
      <String, _EndpointMetricsWindow>{};

  Timer? _summaryTimer;
  int _artworkRequests = 0;
  int _artworkCacheHits = 0;

  Map<String, int> _downloadQueueDepthByUser = <String, int>{};
  Map<String, int> _artworkQueueDepthByUser = <String, int>{};
  int _libraryChangesLagTokens = 0;
  int _libraryLatestToken = 0;
  int _libraryBroadcastToken = 0;

  void start() {
    if (_summaryTimer != null) return;
    _summaryTimer = Timer.periodic(summaryInterval, (_) => _emitSummary());
  }

  void stop() {
    _summaryTimer?.cancel();
    _summaryTimer = null;
  }

  void recordEndpoint({
    required String method,
    required String path,
    required int statusCode,
    required int latencyMs,
    int? payloadBytes,
  }) {
    final endpointKey = '$method $path';
    final window =
        _endpoints.putIfAbsent(endpointKey, () => _EndpointMetricsWindow());
    window.record(
      statusCode: statusCode,
      latencyMs: latencyMs,
      payloadBytes: payloadBytes,
    );
  }

  void recordQueueDepth({
    required Map<String, int> downloadQueueDepthByUser,
    required Map<String, int> artworkQueueDepthByUser,
  }) {
    _downloadQueueDepthByUser = Map<String, int>.from(downloadQueueDepthByUser);
    _artworkQueueDepthByUser = Map<String, int>.from(artworkQueueDepthByUser);
  }

  void recordLibraryChangesLag({
    required int lagTokens,
    required int latestToken,
    required int broadcastToken,
  }) {
    _libraryChangesLagTokens = lagTokens;
    _libraryLatestToken = latestToken;
    _libraryBroadcastToken = broadcastToken;
  }

  void recordArtworkCacheRequest({required bool cacheHit}) {
    _artworkRequests += 1;
    if (cacheHit) {
      _artworkCacheHits += 1;
    }
  }

  void _emitSummary() {
    final endpointSummary = <String, dynamic>{};
    final sortedKeys = _endpoints.keys.toList()..sort();
    for (final key in sortedKeys) {
      endpointSummary[key] = _endpoints[key]!.toSummary();
    }

    final artworkHitRatio =
        _artworkRequests == 0 ? 0.0 : _artworkCacheHits / _artworkRequests;

    final summary = <String, dynamic>{
      'type': 'metrics_summary',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'windowSeconds': summaryInterval.inSeconds,
      'endpoints': endpointSummary,
      'queueDepthByUser': {
        'download': _downloadQueueDepthByUser,
        'artwork': _artworkQueueDepthByUser,
      },
      'libraryChangesLag': {
        'lagTokens': _libraryChangesLagTokens,
        'latestToken': _libraryLatestToken,
        'broadcastToken': _libraryBroadcastToken,
      },
      'artworkCacheHitRatio': {
        'ratio': artworkHitRatio,
        'hits': _artworkCacheHits,
        'requests': _artworkRequests,
      },
    };

    print('[Metrics] ${jsonEncode(summary)}');
  }
}

class _EndpointMetricsWindow {
  static const int _maxSamples = 500;
  final Queue<int> _latencySamples = Queue<int>();
  final Queue<int> _payloadSamples = Queue<int>();
  final Map<int, int> _statusCounts = <int, int>{};

  int _requestCount = 0;

  void record({
    required int statusCode,
    required int latencyMs,
    int? payloadBytes,
  }) {
    _requestCount += 1;
    _statusCounts[statusCode] = (_statusCounts[statusCode] ?? 0) + 1;

    _latencySamples.addLast(latencyMs);
    if (_latencySamples.length > _maxSamples) {
      _latencySamples.removeFirst();
    }

    if (payloadBytes != null && payloadBytes >= 0) {
      _payloadSamples.addLast(payloadBytes);
      if (_payloadSamples.length > _maxSamples) {
        _payloadSamples.removeFirst();
      }
    }
  }

  Map<String, dynamic> toSummary() {
    final sortedLatencies = _latencySamples.toList()..sort();
    final p50 = _percentile(sortedLatencies, 0.50);
    final p95 = _percentile(sortedLatencies, 0.95);

    final payloads = _payloadSamples.toList();
    final payloadAvg = payloads.isEmpty
        ? 0
        : payloads.reduce((a, b) => a + b) ~/ payloads.length;
    final payloadMax =
        payloads.isEmpty ? 0 : payloads.reduce((a, b) => a > b ? a : b);

    final statusCounts = <String, int>{};
    final sortedStatuses = _statusCounts.keys.toList()..sort();
    for (final statusCode in sortedStatuses) {
      statusCounts['$statusCode'] = _statusCounts[statusCode]!;
    }

    return {
      'requests': _requestCount,
      'latencyMs': {
        'p50': p50,
        'p95': p95,
      },
      'payloadBytes': {
        'avg': payloadAvg,
        'max': payloadMax,
        'sampleCount': payloads.length,
      },
      'statusCounts': statusCounts,
    };
  }

  int _percentile(List<int> sortedValues, double percentile) {
    if (sortedValues.isEmpty) return 0;
    final index = ((sortedValues.length - 1) * percentile).round();
    return sortedValues[index];
  }
}
