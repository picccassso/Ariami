import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../utils/atomic_file_write.dart';
import '../../utils/secure_file_permissions.dart';
import 'music_discovery_api_key_config.dart';
import 'music_recommendation_models.dart';
import 'music_recommendation_service.dart';

/// Persists household music discovery settings and wishlist beside account data.
class HouseholdMusicDiscoveryStore {
  static const int maxApiKeyBytes = MusicDiscoveryApiKeyConfig.maxApiKeyBytes;
  static const int maxWebhookUrlBytes = 512;
  static const int maxWishlistItems = 200;
  static final Random _random = Random.secure();

  HouseholdMusicDiscoveryStore({required this.filePath});

  final String filePath;

  bool _initialized = false;
  String? _lastFmApiKey;
  String? _feedToken;
  String? _webhookUrl;
  List<MusicRecommendation> _wishlist = const <MusicRecommendation>[];
  Future<void> _mutationQueue = Future<void>.value();

  bool get isInitialized => _initialized;

  String? get lastFmApiKey {
    _ensureInitialized();
    return _lastFmApiKey;
  }

  String get feedToken {
    _ensureInitialized();
    return _feedToken!;
  }

  String? get webhookUrl {
    _ensureInitialized();
    return _webhookUrl;
  }

  List<MusicRecommendation> get wishlist {
    _ensureInitialized();
    return _wishlist;
  }

  /// Loads existing configuration. Missing, malformed, and oversized files
  /// start empty so a damaged optional setting cannot block server startup.
  void initialize() {
    if (_initialized) return;
    try {
      final file = File(filePath);
      if (file.existsSync()) {
        final decoded = jsonDecode(file.readAsStringSync());
        if (decoded is Map<String, dynamic>) {
          _lastFmApiKey = normalizeApiKey(decoded['lastFmApiKey']);
          _feedToken = _normalizeFeedToken(decoded['feedToken']);
          _webhookUrl = normalizeWebhookUrl(decoded['webhookUrl']);
          _wishlist = _parseWishlist(decoded['wishlist']);
        }
      }
    } catch (_) {
      _lastFmApiKey = null;
      _feedToken = null;
      _webhookUrl = null;
      _wishlist = const <MusicRecommendation>[];
    }
    _feedToken ??= _generateFeedToken();
    _initialized = true;
  }

  /// Stores a trimmed, non-empty API key. Mutations are serialized so the
  /// last completed request is also the value left on disk.
  Future<void> save(String value) {
    _ensureInitialized();
    final normalized = normalizeApiKey(value);
    if (normalized == null) {
      throw ArgumentError('Last.fm API key is empty or too large');
    }
    return _enqueue(() async {
      _lastFmApiKey = normalized;
      await _persistOrDelete();
    });
  }

  /// Stores [value] only while the household has no key. This makes automatic
  /// client migration deterministic when two owner devices reconnect at once.
  Future<bool> saveIfEmpty(String value) async {
    _ensureInitialized();
    final normalized = normalizeApiKey(value);
    if (normalized == null) {
      throw ArgumentError('Last.fm API key is empty or too large');
    }
    var saved = false;
    await _enqueue(() async {
      if (_lastFmApiKey != null) return;
      _lastFmApiKey = normalized;
      await _persistOrDelete();
      saved = true;
    });
    return saved;
  }

  Future<void> clear() {
    _ensureInitialized();
    return _enqueue(() async {
      _lastFmApiKey = null;
      await _persistOrDelete();
    });
  }

  Future<void> saveWebhookUrl(String? value) {
    _ensureInitialized();
    final trimmed = value?.trim() ?? '';
    final String? normalized;
    if (trimmed.isEmpty) {
      normalized = null;
    } else {
      normalized = normalizeWebhookUrl(trimmed);
      if (normalized == null) {
        throw ArgumentError('Webhook URL must be an HTTP/HTTPS URL <= $maxWebhookUrlBytes bytes');
      }
    }
    return _enqueue(() async {
      _webhookUrl = normalized;
      await _persistOrDelete();
    });
  }

  Future<String> rotateFeedToken() async {
    _ensureInitialized();
    late String token;
    await _enqueue(() async {
      token = _generateFeedToken();
      _feedToken = token;
      await _writeFile();
    });
    return token;
  }

  Future<void> ensureFeedTokenPersisted() {
    _ensureInitialized();
    return _enqueue(() async {
      if (!await File(filePath).exists()) {
        await _writeFile();
      }
    });
  }

  Future<MusicRecommendation> addWishlistItem(MusicRecommendation item) async {
    _ensureInitialized();
    late MusicRecommendation saved;
    await _enqueue(() async {
      final key = item.identityKey;
      final existing = _wishlist.where((e) => e.identityKey == key).firstOrNull;
      saved = item.copyWith(
        artistMusicBrainzId:
            item.artistMusicBrainzId ?? existing?.artistMusicBrainzId,
        savedAt: item.savedAt ?? DateTime.now().toUtc(),
      );
      _wishlist = List<MusicRecommendation>.unmodifiable(
        <MusicRecommendation>[
          saved,
          ..._wishlist.where((e) => e.identityKey != key),
        ].take(maxWishlistItems),
      );
      await _writeFile();
    });
    return saved;
  }

  Future<bool> removeWishlistItem(String identityKey) async {
    _ensureInitialized();
    final target = identityKey.trim().toLowerCase();
    var removed = false;
    await _enqueue(() async {
      final next = _wishlist
          .where((item) => item.identityKey != target)
          .toList(growable: false);
      if (next.length == _wishlist.length) return;
      _wishlist = List<MusicRecommendation>.unmodifiable(next);
      await _persistOrDelete();
      removed = true;
    });
    return removed;
  }

  Future<int> removeOwnedWishlistItems(OwnedMusicIndex owned) async {
    _ensureInitialized();
    if (_wishlist.isEmpty || owned.isEmpty) return 0;
    var removed = 0;
    await _enqueue(() async {
      final next = _wishlist
          .where((item) => !owned.containsRecommendation(item))
          .toList(growable: false);
      removed = _wishlist.length - next.length;
      if (removed == 0) return;
      _wishlist = List<MusicRecommendation>.unmodifiable(next);
      await _persistOrDelete();
    });
    return removed;
  }

  void close() {
    _initialized = false;
    _lastFmApiKey = null;
    _feedToken = null;
    _webhookUrl = null;
    _wishlist = const <MusicRecommendation>[];
    _mutationQueue = Future<void>.value();
  }

  static String? normalizeApiKey(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim();
    if (normalized.isEmpty || utf8.encode(normalized).length > maxApiKeyBytes) {
      return null;
    }
    return normalized;
  }

  static String? normalizeWebhookUrl(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim();
    if (normalized.isEmpty ||
        utf8.encode(normalized).length > maxWebhookUrlBytes) {
      return null;
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return null;
    }
    return normalized;
  }

  static String? _normalizeFeedToken(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || utf8.encode(trimmed).length > 128) return null;
    return trimmed;
  }

  static String _generateFeedToken() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static List<MusicRecommendation> _parseWishlist(Object? raw) {
    if (raw is! List<dynamic>) return const <MusicRecommendation>[];
    final seen = <String>{};
    final items = <MusicRecommendation>[];
    for (final entry in raw.whereType<Map<String, dynamic>>()) {
      final item = MusicRecommendation.fromJson(entry);
      if (item.name.trim().isEmpty || !item.lastFmUrl.hasScheme) continue;
      if (seen.add(item.identityKey)) {
        items.add(item);
        if (items.length >= maxWishlistItems) break;
      }
    }
    return List<MusicRecommendation>.unmodifiable(items);
  }

  Future<void> _enqueue(Future<void> Function() action) {
    _mutationQueue = _mutationQueue.catchError((_) {}).then((_) => action());
    return _mutationQueue;
  }

  Future<void> _persistOrDelete() async {
    if (_lastFmApiKey == null && _webhookUrl == null && _wishlist.isEmpty) {
      final file = File(filePath);
      if (await file.exists()) await file.delete();
      return;
    }
    await _writeFile();
  }

  Future<void> _writeFile() async {
    final file = File(filePath);
    final directory = file.parent;
    if (!await directory.exists()) await directory.create(recursive: true);
    await SecureFilePermissions.restrictDirectory(directory.path);
    await writeFileAtomically(
      filePath,
      jsonEncode(<String, dynamic>{
        'schemaVersion': 1,
        if (_lastFmApiKey != null) 'lastFmApiKey': _lastFmApiKey,
        if (_feedToken != null) 'feedToken': _feedToken,
        if (_webhookUrl != null) 'webhookUrl': _webhookUrl,
        if (_wishlist.isNotEmpty)
          'wishlist': _wishlist.map((item) => item.toJson()).toList(),
      }),
      ownerOnly: true,
    );
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
        'HouseholdMusicDiscoveryStore not initialized. Call initialize() first.',
      );
    }
  }
}
