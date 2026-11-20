import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../player/services/player_host.dart';

extension type _MediaSessionActionDetails._(JSObject _) implements JSObject {
  external double? get seekTime;
}

class WebMediaControlsBackend implements MediaControlsBackend {
  static const List<String> _actions = <String>[
    'play',
    'pause',
    'stop',
    'previoustrack',
    'nexttrack',
    'seekto',
  ];

  String? _currentTrackId;
  String _title = '';
  String _artist = '';
  String _album = '';
  String? _artworkUrl;

  web.MediaSession? get _session {
    final nav = web.window.navigator as JSObject;
    if (!nav.has('mediaSession')) return null;
    final raw = nav.getProperty('mediaSession'.toJS);
    if (raw == null || raw.isUndefinedOrNull) return null;
    return raw as web.MediaSession;
  }

  @override
  Future<void> initialize(MediaCommandHandler onCommand) async {
    final session = _session;
    if (session == null) return;
    _setHandler(
      session,
      'play',
      (() => onCommand(MediaControlCommand.play)).toJS,
    );
    _setHandler(
      session,
      'pause',
      (() => onCommand(MediaControlCommand.pause)).toJS,
    );
    _setHandler(
      session,
      'stop',
      (() => onCommand(MediaControlCommand.stop)).toJS,
    );
    _setHandler(
      session,
      'previoustrack',
      (() => onCommand(MediaControlCommand.previous)).toJS,
    );
    _setHandler(
      session,
      'nexttrack',
      (() => onCommand(MediaControlCommand.next)).toJS,
    );
    _setHandler(
      session,
      'seekto',
      ((_MediaSessionActionDetails? details) {
        final seekTime = details?.seekTime;
        if (seekTime == null || !seekTime.isFinite || seekTime < 0) return;
        onCommand(
          MediaControlCommand.seek,
          Duration(milliseconds: (seekTime * 1000).round()),
        );
      }).toJS,
    );
  }

  void _setHandler(
    web.MediaSession session,
    String action,
    JSFunction? handler,
  ) {
    try {
      session.setActionHandler(action, handler);
    } catch (_) {}
  }

  @override
  Future<void> setMetadata(MediaNowPlaying info) async {
    final session = _session;
    if (session == null) return;
    if (_currentTrackId != info.id) {
      _revokeArtworkUrl();
      _currentTrackId = info.id;
    }
    _title = info.title;
    _artist = info.artist;
    _album = info.album;
    _applyMetadata(session);
    await setPlaybackState(
      isPlaying: info.isPlaying,
      position: info.position,
      duration: info.duration,
    );
  }

  @override
  Future<void> setArtwork(String trackId, Uint8List bytes) async {
    final session = _session;
    if (session == null || trackId != _currentTrackId || bytes.isEmpty) return;
    final mime = _sniffImageMime(bytes);
    final blob = web.Blob(
      <web.BlobPart>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: mime),
    );
    _revokeArtworkUrl();
    _artworkUrl = web.URL.createObjectURL(blob);
    _applyMetadata(session, artworkMime: mime);
  }

  @override
  Future<void> setPlaybackState({
    required bool isPlaying,
    required Duration position,
    required Duration duration,
  }) async {
    final session = _session;
    if (session == null) return;
    try {
      session.playbackState = isPlaying ? 'playing' : 'paused';
    } catch (_) {}

    final durationSec = duration.inMilliseconds / 1000.0;
    if (durationSec > 0 && durationSec.isFinite) {
      final positionSec = (position.inMilliseconds / 1000.0).clamp(
        0.0,
        durationSec,
      );
      try {
        session.setPositionState(
          web.MediaPositionState(
            duration: durationSec,
            playbackRate: 1.0,
            position: positionSec,
          ),
        );
      } catch (_) {}
    }
  }

  @override
  Future<void> clear() async {
    _revokeArtworkUrl();
    _currentTrackId = null;
    _title = '';
    _artist = '';
    _album = '';
    final session = _session;
    if (session == null) return;
    try {
      session.metadata = null;
      session.playbackState = 'none';
      session.setPositionState();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    final session = _session;
    if (session != null) {
      for (final action in _actions) {
        _setHandler(session, action, null);
      }
    }
    await clear();
  }

  void _applyMetadata(web.MediaSession session, {String? artworkMime}) {
    final url = _artworkUrl;
    final artwork = (url != null)
        ? <web.MediaImage>[
            web.MediaImage(
              src: url,
              type: artworkMime ?? 'image/jpeg',
            ),
          ].toJS
        : <web.MediaImage>[].toJS;
    try {
      session.metadata = web.MediaMetadata(
        web.MediaMetadataInit(
          title: _title,
          artist: _artist,
          album: _album,
          artwork: artwork,
        ),
      );
    } catch (_) {}
  }

  void _revokeArtworkUrl() {
    final url = _artworkUrl;
    if (url == null) return;
    _artworkUrl = null;
    try {
      web.URL.revokeObjectURL(url);
    } catch (_) {}
  }

  static String _sniffImageMime(Uint8List bytes) {
    if (bytes.length >= 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }
}
