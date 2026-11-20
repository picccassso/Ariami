import 'package:flutter/foundation.dart';
import 'package:ariami_core/models/lyrics_models.dart';

import 'audio_controller.dart';
import 'player_api_client.dart';
import 'player_host.dart';

/// State management and data resolution for lyrics playback.
class LyricsController extends ChangeNotifier {
  AudioController? _audio;
  PlayerDownloadsBridge? _downloads;
  PlayerApiClient? _client;

  bool _lyricsPreferred = false;

  /// The user's single "show lyrics" choice, shared by the right panel and
  /// the fullscreen player. It survives tracks without lyrics, which fall
  /// back to artwork/queue until a track with lyrics plays again.
  bool get lyricsPreferred => _lyricsPreferred;

  SongLyrics? _currentLyrics;
  SongLyrics? get currentLyrics => _currentLyrics;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _hasLyrics = false;

  /// Whether the current track has lyrics (server-flagged or downloaded).
  bool get hasLyrics => _hasLyrics;

  /// Whether lyrics should show: preferred by the user AND available.
  bool get isLyricsActive => _lyricsPreferred && _hasLyrics;

  String? _loadedSongId;
  final Map<String, SongLyrics> _cache = <String, SongLyrics>{};

  bool _disposed = false;

  void attach({
    required AudioController audio,
    PlayerDownloadsBridge? downloads,
    PlayerApiClient? client,
  }) {
    if (identical(_audio, audio) &&
        identical(_downloads, downloads) &&
        identical(_client, client)) {
      return;
    }
    _audio?.removeListener(_onAudioChanged);
    _downloads?.removeListener(_onDownloadsChanged);

    _audio = audio;
    _downloads = downloads;
    _client = client;

    _audio?.addListener(_onAudioChanged);
    _downloads?.addListener(_onDownloadsChanged);
    _syncTrack();
  }

  void updateClient(PlayerApiClient? client) {
    if (identical(_client, client)) return;
    _client = client;
    _loadIfNeeded();
  }

  void toggleLyricsPreferred() => setLyricsPreferred(!_lyricsPreferred);

  void setLyricsPreferred(bool preferred) {
    if (_lyricsPreferred == preferred) return;
    _lyricsPreferred = preferred;
    notifyListeners();
    _loadIfNeeded();
  }

  bool _computeHasLyrics() {
    final track = _audio?.currentTrack;
    return track != null &&
        (track.hasLyrics ||
            (_downloads?.hasDownloadedLyrics(track.id) ?? false));
  }

  void _onAudioChanged() {
    if (_audio?.currentTrack?.id != _loadedSongId) _syncTrack();
  }

  // Download progress notifies often; only resync when it changes the answer.
  void _onDownloadsChanged() {
    if (_computeHasLyrics() != _hasLyrics) _syncTrack();
  }

  void _syncTrack() {
    final songId = _audio?.currentTrack?.id;
    _loadedSongId = songId;
    _hasLyrics = _computeHasLyrics();
    _currentLyrics = _hasLyrics ? _cache[songId] : null;
    _isLoading = false;
    notifyListeners();
    _loadIfNeeded();
  }

  /// Lyrics load lazily: only once the user wants them shown.
  Future<void> _loadIfNeeded() async {
    final songId = _audio?.currentTrack?.id;
    if (!isLyricsActive || _currentLyrics != null || _isLoading) return;
    if (songId == null) return;

    _isLoading = true;
    notifyListeners();
    final lyrics = await getLyrics(songId);
    // A track change resets loading state and starts its own load.
    if (_disposed || _audio?.currentTrack?.id != songId) return;
    _currentLyrics = lyrics;
    _isLoading = false;
    notifyListeners();
  }

  /// Resolves lyrics for any song: cached, then downloaded, then network.
  Future<SongLyrics?> getLyrics(String songId) async {
    final cached = _cache[songId];
    if (cached != null) return cached;
    final lyrics = await _downloads?.lyricsFor(songId) ??
        await _client?.fetchLyrics(songId);
    if (lyrics != null) _cache[songId] = lyrics;
    return lyrics;
  }

  @override
  void dispose() {
    _disposed = true;
    _audio?.removeListener(_onAudioChanged);
    _downloads?.removeListener(_onDownloadsChanged);
    super.dispose();
  }
}
