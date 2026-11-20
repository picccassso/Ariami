import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../player/services/player_host.dart';
import 'web_audio_backends_stub.dart'
    if (dart.library.js_interop) 'web_audio_backends.dart';
import 'web_media_controls_stub.dart'
    if (dart.library.js_interop) 'web_media_controls_backend.dart';
import 'web_platform_stub.dart'
    if (dart.library.js_interop) 'web_platform_actions.dart';
import 'web_storage_stub.dart'
    if (dart.library.js_interop) 'web_storage.dart';

AudioPlayer _createWebAudioPlayer() {
  final player = AudioPlayer();
  unawaited(player.setWebCrossOrigin(WebCrossOrigin.anonymous));
  return player;
}

PlayerHost createWebPlayerHost() {
  final deviceName = detectWebDeviceName();
  return PlayerHost(
    sessionTokenStore: PrefsSessionTokenStore(),
    artworkCacheStore: createWebArtworkCacheStore(),
    listeningOutboxStore: PrefsListeningOutboxStore(),
    librarySnapshotStore: createWebLibrarySnapshotStore(),
    equalizerBackend: WebAudioEqualizerBackend(),
    levelMeterBackend: WebAudioLevelMeterBackend(),
    mediaControlsBackend: WebMediaControlsBackend(),
    statsShareHandler: WebStatsShareHandler(),
    spotifyFilePicker: WebSpotifyExportPicker(),
    clientType: 'web',
    defaultDeviceName: deviceName,
    apiDeviceName: deviceName,
    deviceIdPrefix: 'web_client_',
    platformLabel: 'web',
    statsClientKind: 'web',
    sameOriginUri: resolveWebSameOriginUri(),
    createAudioPlayer: _createWebAudioPlayer,
    onAudioStateChanged: updateWebDocumentTitle,
  );
}
