import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/player_models.dart';
import '../widgets/artwork_image_provider.dart';
import 'audio_controller.dart';
import 'player_api_client.dart';
import 'player_host.dart';

class MediaControlsService {
  AudioController? _audio;
  PlayerApiClient? _client;
  MediaControlsBackend? _backend;
  bool _started = false;

  String? _lastTrackId;
  bool? _lastPlaying;
  int _lastPositionPushMs = 0;
  int _artworkRequest = 0;

  static const _positionPushIntervalMs = 3000;

  void start(AudioController audio, {MediaControlsBackend? backend}) {
    if (_started || backend == null) return;
    _started = true;
    _audio = audio;
    _backend = backend;
    backend.initialize(_handleCommand).then((_) {
      audio.addTickingListener(_onAudioChanged);
      _onAudioChanged();
    }).catchError((Object e) {
      debugPrint('[MediaControls] backend init failed: $e');
    });
  }

  void updateClient(PlayerApiClient? client) {
    _client = client;
  }

  void dispose() {
    _audio?.removeTickingListener(_onAudioChanged);
    unawaited(_backend?.dispose());
    _backend = null;
  }

  void _handleCommand(MediaControlCommand command, [Duration? seekTo]) {
    final audio = _audio;
    if (audio == null) return;
    switch (command) {
      case MediaControlCommand.play:
        unawaited(audio.resume());
        break;
      case MediaControlCommand.pause:
      case MediaControlCommand.stop:
        unawaited(audio.pause());
        break;
      case MediaControlCommand.toggle:
        unawaited(audio.togglePlayPause());
        break;
      case MediaControlCommand.next:
        unawaited(audio.next());
        break;
      case MediaControlCommand.previous:
        unawaited(audio.previous());
        break;
      case MediaControlCommand.seek:
        if (seekTo != null) unawaited(audio.seek(seekTo));
        break;
    }
  }

  void _onAudioChanged() {
    final audio = _audio;
    final backend = _backend;
    if (audio == null || backend == null) return;

    final track = audio.currentTrack;
    if (track == null) {
      if (_lastTrackId != null) {
        _lastTrackId = null;
        _lastPlaying = null;
        unawaited(backend.clear());
      }
      return;
    }

    if (track.id != _lastTrackId) {
      _lastTrackId = track.id;
      _lastPlaying = audio.isPlaying;
      _lastPositionPushMs = DateTime.now().millisecondsSinceEpoch;
      unawaited(backend.setMetadata(_snapshot(track, audio)));
      unawaited(_attachArtwork(track));
      return;
    }

    final playing = audio.isPlaying;
    final now = DateTime.now().millisecondsSinceEpoch;
    final stateChanged = playing != _lastPlaying;
    final driftDue =
        playing && now - _lastPositionPushMs > _positionPushIntervalMs;
    if (stateChanged || driftDue) {
      _lastPlaying = playing;
      _lastPositionPushMs = now;
      unawaited(backend.setPlaybackState(
        isPlaying: playing,
        position: audio.position,
        duration: audio.duration ?? track.duration,
      ));
    }
  }

  MediaNowPlaying _snapshot(Track track, AudioController audio) {
    return MediaNowPlaying(
      id: track.id,
      title: track.title,
      artist: track.artist,
      album: track.albumTitle ?? '',
      duration: audio.duration ?? track.duration,
      position: audio.position,
      isPlaying: audio.isPlaying,
    );
  }

  Future<void> _attachArtwork(Track track) async {
    final client = _client;
    final backend = _backend;
    if (client == null || backend == null) return;
    final request = ++_artworkRequest;

    final url = (track.albumId != null && track.albumId!.isNotEmpty)
        ? client.albumArtworkUrl(track.albumId!, thumbnail: true)
        : client.songArtworkUrl(track.id, thumbnail: true);

    Uint8List? bytes;
    try {
      final loaded = await ArtworkImageProvider.loadBytes(
        url,
        headers: client.artworkHeaders,
      );
      if (loaded.isNotEmpty) bytes = loaded;
    } catch (_) {
      // Artwork is optional.
    }

    if (bytes == null ||
        request != _artworkRequest ||
        track.id != _lastTrackId) {
      return;
    }
    unawaited(backend.setArtwork(track.id, bytes));
  }
}
