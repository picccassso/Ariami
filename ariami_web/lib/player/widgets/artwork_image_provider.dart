import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:ariami_core/models/artwork_batch_codec.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

import '../services/player_api_client.dart';
import '../services/player_host.dart';

class ArtworkCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class _CancelledArtworkLoad implements Exception {
  const _CancelledArtworkLoad();
}

class _FetchWaiter {
  _FetchWaiter(this.completer, this.tokens);

  final Completer<bool> completer;
  final List<ArtworkCancelToken?> tokens;

  bool get isCancelled =>
      tokens.isNotEmpty && tokens.every((t) => t != null && t.isCancelled);
}

/// An [ImageProvider] for authenticated server artwork with an optional
/// persistent [ArtworkCacheStore], LIFO cancellation, URL deduplication,
/// negative 404 caching, and 1-RTT batch prefetching.
@immutable
class ArtworkImageProvider extends ImageProvider<ArtworkImageProvider> {
  const ArtworkImageProvider(
    this.url, {
    this.headers,
    this.scale = 1.0,
    this.cancelToken,
  });

  /// Fully-qualified artwork URL (the auth token travels in [headers]).
  final String url;

  final Map<String, String>? headers;

  final double scale;

  final ArtworkCancelToken? cancelToken;

  static final http.Client _httpClient = http.Client();
  static ArtworkCacheStore? cacheStore;

  /// Address-independent identity of the connected server/library.
  static String cacheScope = '';

  static const int _maxConcurrentNetworkFetches = 6;
  static int _activeNetworkFetches = 0;
  static int _activeForegroundFetches = 0;
  static DateTime _lastForegroundActivity = DateTime.fromMillisecondsSinceEpoch(0);
  static final List<_FetchWaiter> _foregroundWaiters = <_FetchWaiter>[];
  static final Queue<_FetchWaiter> _backgroundWaiters = Queue<_FetchWaiter>();

  static final Map<String, Future<Uint8List>> _inFlight =
      <String, Future<Uint8List>>{};
  static final Map<String, List<ArtworkCancelToken?>> _inFlightTokens =
      <String, List<ArtworkCancelToken?>>{};
  static final Set<String> _missingUrls = <String>{};
  static final Set<String> _knownCachedIdentities = <String>{};
  static bool _batchUnsupported = false;

  static bool get hasForegroundActivity =>
      _activeForegroundFetches > 0 ||
      _foregroundWaiters.isNotEmpty ||
      DateTime.now().difference(_lastForegroundActivity) <
          const Duration(seconds: 3);

  static void resetSessionState() {
    _missingUrls.clear();
    _knownCachedIdentities.clear();
    _batchUnsupported = false;
  }

  static bool isKnownMissing(String url) => _missingUrls.contains(url);

  static Future<bool> _acquireFetchSlot({
    required bool background,
    required List<ArtworkCancelToken?> tokens,
  }) {
    if (_activeNetworkFetches < _maxConcurrentNetworkFetches) {
      _activeNetworkFetches++;
      if (!background) {
        _activeForegroundFetches++;
        _lastForegroundActivity = DateTime.now();
      }
      return SynchronousFuture<bool>(true);
    }
    final completer = Completer<bool>();
    final waiter = _FetchWaiter(completer, tokens);
    if (background) {
      _backgroundWaiters.add(waiter);
    } else {
      _lastForegroundActivity = DateTime.now();
      _foregroundWaiters.add(waiter);
    }
    return completer.future;
  }

  static void _releaseFetchSlot({required bool background}) {
    if (!background && _activeForegroundFetches > 0) {
      _activeForegroundFetches--;
    }
    // Serve newest foreground requests first (LIFO), skipping cancelled rows.
    while (_foregroundWaiters.isNotEmpty) {
      final next = _foregroundWaiters.removeLast();
      if (next.isCancelled) {
        next.completer.complete(false);
        continue;
      }
      _activeForegroundFetches++;
      next.completer.complete(true);
      return;
    }
    while (_backgroundWaiters.isNotEmpty) {
      final next = _backgroundWaiters.removeFirst();
      if (next.isCancelled) {
        next.completer.complete(false);
        continue;
      }
      next.completer.complete(true);
      return;
    }
    if (_activeNetworkFetches > 0) {
      _activeNetworkFetches--;
    }
  }

  @override
  Future<ArtworkImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<ArtworkImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    ArtworkImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: key.scale,
      debugLabel: key.url,
    );
  }

  Future<ui.Codec> _loadAsync(
    ArtworkImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    final bytes = await _resolveBytes(key);
    if (bytes.isEmpty) {
      throw StateError('Artwork response was empty: ${key.url}');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  Future<Uint8List> _resolveBytes(ArtworkImageProvider key) => loadBytes(
        key.url,
        headers: key.headers,
        cancelToken: key.cancelToken,
      );

  /// Asks for the server's 640px variant when that covers [cacheWidth];
  /// servers without it ignore `size` and send the original.
  static String sizedUrl(String url, int cacheWidth) {
    if (cacheWidth > 640) return url;
    final uri = Uri.parse(url);
    return uri.replace(
      queryParameters: {...uri.queryParameters, 'size': 'medium'},
    ).toString();
  }

  static Future<Uint8List> loadBytes(
    String url, {
    Map<String, String>? headers,
    ArtworkCancelToken? cancelToken,
    bool background = false,
  }) {
    if (_missingUrls.contains(url)) {
      return Future<Uint8List>.error(
        http.ClientException('Artwork not found (cached 404)', Uri.parse(url)),
      );
    }

    final existing = _inFlight[url];
    if (existing != null) {
      _inFlightTokens[url]?.add(cancelToken);
      return existing;
    }

    final tokens = <ArtworkCancelToken?>[cancelToken];
    _inFlightTokens[url] = tokens;
    final future = _fetchSingle(
      url,
      headers: headers,
      tokens: tokens,
      background: background,
    );
    _inFlight[url] = future;
    future.whenComplete(() {
      if (identical(_inFlight[url], future)) {
        _inFlight.remove(url);
        _inFlightTokens.remove(url);
      }
    }).ignore();
    return future;
  }

  static Future<Uint8List> _fetchSingle(
    String url, {
    Map<String, String>? headers,
    required List<ArtworkCancelToken?> tokens,
    required bool background,
  }) async {
    final store = cacheStore;
    final identity = store != null ? cacheIdentityFor(url) : null;
    if (store != null && identity != null) {
      try {
        final cached = await store.read(identity);
        if (cached != null && cached.isNotEmpty) {
          _knownCachedIdentities.add(identity);
          return cached;
        }
      } catch (_) {}
    }

    if (tokens.every((t) => t != null && t.isCancelled)) {
      throw const _CancelledArtworkLoad();
    }

    final acquired = await _acquireFetchSlot(
      background: background,
      tokens: tokens,
    );
    if (!acquired) {
      throw const _CancelledArtworkLoad();
    }

    final http.Response response;
    try {
      response = await _httpClient.get(Uri.parse(url), headers: headers);
    } finally {
      _releaseFetchSlot(background: background);
    }

    if (response.statusCode == 404) {
      _missingUrls.add(url);
      throw http.ClientException(
        'Artwork request failed (HTTP 404)',
        Uri.parse(url),
      );
    }
    if (response.statusCode != 200) {
      throw http.ClientException(
        'Artwork request failed (HTTP ${response.statusCode})',
        Uri.parse(url),
      );
    }

    final bytes = response.bodyBytes;
    if (store != null && identity != null && bytes.isNotEmpty) {
      _knownCachedIdentities.add(identity);
      unawaited(store.write(identity, bytes));
    }
    return bytes;
  }

  /// Synchronously claims in-flight futures for [albumIds] and [songIds] so
  /// widgets building right after search settle share a single `/api/artwork/batch`
  /// round-trip instead of firing individual GETs.
  static Future<void> prefetchBatch(
    PlayerApiClient client, {
    Iterable<String> albumIds = const <String>[],
    Iterable<String> songIds = const <String>[],
    bool background = false,
  }) {
    if (_batchUnsupported) return SynchronousFuture<void>(null);

    final store = cacheStore;
    final candidates = <({
      String batchKey,
      String id,
      bool isAlbum,
      String url,
      String identity,
      Completer<Uint8List> completer,
    })>[];

    void addCandidate(String id, {required bool isAlbum}) {
      if (id.isEmpty || candidates.length >= 50) return;
      final url = isAlbum
          ? client.albumArtworkUrl(id, thumbnail: true)
          : client.songArtworkUrl(id, thumbnail: true);
      final identity = cacheIdentityFor(url);
      if (_knownCachedIdentities.contains(identity) ||
          _missingUrls.contains(url) ||
          _inFlight.containsKey(url)) {
        return;
      }
      final completer = Completer<Uint8List>();
      // Prevent unhandled async error if no widget awaits a missing cover.
      completer.future.ignore();
      _inFlight[url] = completer.future;
      candidates.add((
        batchKey: isAlbum
            ? ArtworkBatchCodec.albumKey(id)
            : ArtworkBatchCodec.songKey(id),
        id: id,
        isAlbum: isAlbum,
        url: url,
        identity: identity,
        completer: completer,
      ));
    }

    for (final id in albumIds) {
      addCandidate(id, isAlbum: true);
    }
    for (final id in songIds) {
      addCandidate(id, isAlbum: false);
    }

    if (candidates.isEmpty) return SynchronousFuture<void>(null);

    if (!background) {
      _activeForegroundFetches++;
      _lastForegroundActivity = DateTime.now();
    }

    return () async {
      final uncached = <({
        String batchKey,
        String id,
        bool isAlbum,
        String url,
        String identity,
        Completer<Uint8List> completer,
      })>[];

      try {
        if (store != null) {
          final reads = await Future.wait(
            candidates.map((c) async {
              try {
                return await store.read(c.identity);
              } catch (_) {
                return null;
              }
            }),
          );
          for (var i = 0; i < candidates.length; i++) {
            final c = candidates[i];
            final cached = reads[i];
            if (cached != null && cached.isNotEmpty) {
              _knownCachedIdentities.add(c.identity);
              _inFlight.remove(c.url);
              if (!c.completer.isCompleted) c.completer.complete(cached);
            } else {
              uncached.add(c);
            }
          }
        } else {
          uncached.addAll(candidates);
        }

        if (uncached.isEmpty) return;

        final batchAlbums = [
          for (final c in uncached)
            if (c.isAlbum) c.id,
        ];
        final batchSongs = [
          for (final c in uncached)
            if (!c.isAlbum) c.id,
        ];

        final items = await client.fetchArtworkBatch(
          albumIds: batchAlbums,
          songIds: batchSongs,
        );

        if (items == null) {
          _batchUnsupported = true;
          for (final c in uncached) {
            _inFlight.remove(c.url);
            if (!c.completer.isCompleted) {
              if (background) {
                c.completer.completeError(
                  http.ClientException('Batch unsupported', Uri.parse(c.url)),
                );
              } else {
                loadBytes(c.url, headers: client.artworkHeaders).then(
                  (bytes) {
                    if (!c.completer.isCompleted) c.completer.complete(bytes);
                  },
                  onError: (Object err, StackTrace st) {
                    if (!c.completer.isCompleted) {
                      c.completer.completeError(err, st);
                    }
                  },
                );
              }
            }
          }
          return;
        }

        final byKey = <String, ArtworkBatchItem>{
          for (final item in items) item.key: item,
        };

        for (final c in uncached) {
          _inFlight.remove(c.url);
          final item = byKey[c.batchKey];
          if (item != null && item.found) {
            final bytes = item.bytes!;
            if (store != null) {
              _knownCachedIdentities.add(c.identity);
              unawaited(store.write(c.identity, bytes));
            }
            if (!c.completer.isCompleted) c.completer.complete(bytes);
          } else {
            _missingUrls.add(c.url);
            if (!c.completer.isCompleted) {
              c.completer.completeError(
                http.ClientException(
                  'Artwork not found in batch',
                  Uri.parse(c.url),
                ),
              );
            }
          }
        }
      } catch (err, st) {
        for (final c in candidates) {
          _inFlight.remove(c.url);
          if (!c.completer.isCompleted) {
            c.completer.completeError(err, st);
          }
        }
      } finally {
        if (!background && _activeForegroundFetches > 0) {
          _activeForegroundFetches--;
          _lastForegroundActivity = DateTime.now();
        }
      }
    }();
  }

  @visibleForTesting
  static String cacheIdentityFor(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '$cacheScope|$url';
    final resource = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
    return '$cacheScope|$resource';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ArtworkImageProvider &&
        other.url == url &&
        other.scale == scale;
  }

  @override
  int get hashCode => Object.hash(url, scale);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'ArtworkImageProvider')}("$url", scale: $scale)';
}
