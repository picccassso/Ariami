import 'package:ariami_core/models/lyrics_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/player_models.dart';
import 'audio_controller.dart';
import 'connection_controller.dart';
import 'player_api_client.dart';

abstract class SessionTokenStore {
  Future<String?> read(String key, {SharedPreferences? legacyPrefs});
  Future<void> write(
    String key,
    String value, {
    SharedPreferences? legacyPrefs,
  });
  Future<void> delete(String key, {SharedPreferences? legacyPrefs});
  Future<void> clearAll();
}

/// SharedPreferences-backed token store for platforms without a native keychain
/// (such as plain-HTTP web origins where WebCrypto / Credential Management are unavailable).
class PrefsSessionTokenStore implements SessionTokenStore {
  PrefsSessionTokenStore({this.keyPrefix = 'player_session_token_'});

  final String keyPrefix;

  @override
  Future<String?> read(String key, {SharedPreferences? legacyPrefs}) async {
    final prefs = legacyPrefs ?? await SharedPreferences.getInstance();
    final value = prefs.getString(key);
    return (value != null && value.isNotEmpty) ? value : null;
  }

  @override
  Future<void> write(
    String key,
    String value, {
    SharedPreferences? legacyPrefs,
  }) async {
    final prefs = legacyPrefs ?? await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  @override
  Future<void> delete(String key, {SharedPreferences? legacyPrefs}) async {
    final prefs = legacyPrefs ?? await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  @override
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().toList(growable: false)) {
      if (key.startsWith(keyPrefix)) {
        await prefs.remove(key);
      }
    }
  }
}

abstract class ArtworkCacheStore {
  Future<Uint8List?> read(String identity);
  Future<void> write(String identity, Uint8List bytes);
}

abstract class LibrarySnapshotStore {
  Future<String?> read(String scope);
  Future<void> write(String scope, String contents);
  Future<String?> readLastScope();
  Future<void> writeLastScope(String scope);
}

abstract class ListeningOutboxStore {
  Future<String?> read();
  Future<void> write(String contents);
}

class PrefsListeningOutboxStore implements ListeningOutboxStore {
  PrefsListeningOutboxStore({
    this.preferenceKey = 'ariami_listening_events_outbox_v1',
  });

  final String preferenceKey;

  @override
  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(preferenceKey);
  }

  @override
  Future<void> write(String contents) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(preferenceKey, contents);
  }
}

abstract class EqualizerBackend {
  bool get isSupported;

  Future<void> apply({
    required bool enabled,
    required List<int> frequencies,
    required List<double> gains,
  });
}

class LevelMeterReading {
  const LevelMeterReading({
    required this.readings,
    required this.blockSeconds,
    this.latency = Duration.zero,
  });

  final List<List<double>> readings;
  final double blockSeconds;
  final Duration latency;
}

abstract class LevelMeterBackend {
  bool get isSupported;
  Future<void> setEnabled(bool enabled);
  Future<LevelMeterReading?> read();
}

enum MediaControlCommand { play, pause, stop, toggle, next, previous, seek }

typedef MediaCommandHandler = void Function(
  MediaControlCommand command, [
  Duration? seekTo,
]);

class MediaNowPlaying {
  const MediaNowPlaying({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.position,
    required this.isPlaying,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final Duration position;
  final bool isPlaying;
}

abstract class MediaControlsBackend {
  Future<void> initialize(MediaCommandHandler onCommand);
  Future<void> setMetadata(MediaNowPlaying info);
  Future<void> setPlaybackState({
    required bool isPlaying,
    required Duration position,
    required Duration duration,
  });
  Future<void> setArtwork(String trackId, Uint8List bytes);
  Future<void> clear();
  Future<void> dispose();
}

abstract class StatsShareHandler {
  bool get supportsCopy;
  bool get supportsSave => true;
  bool get supportsShare;

  Future<bool> copyPng(Uint8List bytes);
  Future<bool> savePng(Uint8List bytes, String filename);
  Future<void> sharePng(
    Uint8List bytes,
    String filename, {
    Rect? sharePositionOrigin,
  });
}

abstract class SpotifyExportPicker {
  String get idleDescription =>
      'Bring your Spotify listening history into Ariami. Request your '
      '"Extended streaming history" from Spotify\'s privacy settings, '
      'unzip it, then select your Streaming_History_Audio_*.json files here. '
      'Your plays are matched against this library and added to your listening stats.';

  String get chooseLabel => 'Choose Spotify history files';

  Future<List<Map<String, dynamic>>?> pickAndReadRecords();
}

abstract class PlayerDownloadsBridge extends ChangeNotifier {
  bool get hasClient;
  int get inFlightCount;
  int get sessionTotal;
  int get sessionDone;
  double? get sessionProgress;

  String? localPathFor(String songId);
  String? localPathForAtLeast(String songId, StreamQuality minQuality);
  bool hasDownloadedLyrics(String songId);
  Future<SongLyrics?> lyricsFor(String songId);

  ({int completed, int inFlight, double progress}) collectionCounts(
    Iterable<String> songIds,
  );

  bool isDownloaded(String songId);
  bool isQueued(String songId);
  bool isAlbumDownloaded(String albumId, int songCount);
  bool areAllSongsDownloaded(Iterable<String> songIds);
  bool isAnySongDownloaded(Iterable<String> songIds);
  bool hasAlbumDownloads(String albumId);

  int enqueueTracks(
    List<Track> tracks, {
    Map<String, String> albumArtists = const <String, String>{},
  });

  Future<void> removeTrackDownload(String taskId);
  Future<void> removeCollectionDownloads(Iterable<String> songIds);
  void attach(PlayerApiClient? client, {String? accountKey});
  Future<void> attachOffline();
  int refreshAlbumMetadata({
    required Iterable<Album> albums,
    required Iterable<Track> tracks,
  });

  Widget buildSettingsSection();
}

class PlayerCastDevice {
  const PlayerCastDevice({required this.id, required this.name});

  final String id;
  final String name;
}

abstract class PlayerCastBridge extends ChangeNotifier {
  bool get isConnected;
  bool get isDiscoveryActive;
  bool get isRemotePlaying;
  bool get isRemoteBuffering;
  bool get attachedToExistingPlayback;
  String? get connectedDeviceName;
  Duration get remotePosition;
  Duration? get remoteDuration;
  double get deviceVolume;
  List<PlayerCastDevice> get devices;
  VoidCallback? onTrackCompleted;

  Future<void> startDiscovery();
  Future<void> stopDiscovery();
  Future<void> connect(PlayerCastDevice device);
  Future<void> attachToExistingPlayback(PlayerCastDevice device);
  Future<void> disconnect({bool stopReceiver = true});
  Future<bool> syncFromPlayback({
    required Track? track,
    required Duration position,
    required bool isPlaying,
    required PlayerApiClient apiClient,
    StreamQuality quality = StreamQuality.high,
    bool force = false,
  });
  Future<void> resume();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double value);
}

abstract class PlayerDiscordBridge extends ChangeNotifier {
  bool get isEnabled;
  String get statusLabel;
  bool get isError;

  Future<void> setEnabled(bool enabled);
  Future<void> initialize();
  void start(AudioController audio);
}

abstract class PlayerExtraSettings {
  const PlayerExtraSettings();

  Widget? buildGeneralTopCard(BuildContext context) => null;
  Widget? buildLicenseSection(BuildContext context) => null;
  bool get supportsUpdates => false;
  Widget? buildUpdatesSection(BuildContext context) => null;
  Widget? buildServerDashboard(BuildContext context, String sectionId) => null;
}

class DiscoveredLanServer {
  const DiscoveredLanServer({
    required this.name,
    required this.host,
    required this.port,
    this.version = '',
  });

  final String name;
  final String host;
  final int port;
  final String version;

  String get address => '$host:$port';
}

class PlayerAudioState {
  const PlayerAudioState({
    required this.isPlayingHere,
    required this.isPlaying,
    this.currentTrack,
    this.localIsPlaying = false,
    this.localCurrentTrack,
    this.isOfflinePlayback = false,
  });

  final bool isPlayingHere;
  final bool isPlaying;
  final Track? currentTrack;
  final bool localIsPlaying;
  final Track? localCurrentTrack;
  final bool isOfflinePlayback;
}

class PlayerHost {
  PlayerHost({
    SessionTokenStore? sessionTokenStore,
    this.artworkCacheStore,
    this.librarySnapshotStore,
    ListeningOutboxStore? listeningOutboxStore,
    this.equalizerBackend,
    this.levelMeterBackend,
    this.mediaControlsBackend,
    this.statsShareHandler,
    this.spotifyFilePicker,
    this.downloads,
    this.cast,
    this.discord,
    this.extraSettings,
    required this.clientType,
    required this.defaultDeviceName,
    String? apiDeviceName,
    required this.deviceIdPrefix,
    required this.platformLabel,
    required this.statsClientKind,
    this.sameOriginUri,
    this.hasMacWindowChrome = false,
    this.macTrafficLightInset = 0,
    this.windowDragAreaBuilder,
    this.createAudioPlayer,
    this.serverFileResolver,
    this.localFileExists,
    this.localFileLength,
    this.readLocalFileBytes,
    this.onAttachedClientChanged,
    this.onAudioStateChanged,
    this.readLegacyDiscoveryApiKey,
    this.takePendingLocalSignIn,
    this.setupOverlayBuilder,
    this.setupCompletionOverlayBuilder,
    this.takeSetupJustCompleted,
    this.onSignInResetServer,
    this.discoverLanServers,
    this.checkUpdateLabel,
    this.onOpenUpdates,
  })  : sessionTokenStore = sessionTokenStore ?? PrefsSessionTokenStore(),
        listeningOutboxStore =
            listeningOutboxStore ?? PrefsListeningOutboxStore(),
        apiDeviceName = apiDeviceName ?? defaultDeviceName;

  final SessionTokenStore sessionTokenStore;
  final ArtworkCacheStore? artworkCacheStore;
  final LibrarySnapshotStore? librarySnapshotStore;
  final ListeningOutboxStore listeningOutboxStore;

  final EqualizerBackend? equalizerBackend;
  final LevelMeterBackend? levelMeterBackend;
  final MediaControlsBackend? mediaControlsBackend;
  final StatsShareHandler? statsShareHandler;
  final SpotifyExportPicker? spotifyFilePicker;

  final PlayerDownloadsBridge? downloads;
  final PlayerCastBridge? cast;
  final PlayerDiscordBridge? discord;
  final PlayerExtraSettings? extraSettings;

  final String clientType;
  final String defaultDeviceName;
  final String apiDeviceName;
  final String deviceIdPrefix;
  final String platformLabel;
  final String statsClientKind;
  final Uri? sameOriginUri;

  final bool hasMacWindowChrome;
  final double macTrafficLightInset;
  final Widget Function(Widget child)? windowDragAreaBuilder;

  final AudioPlayer Function()? createAudioPlayer;
  final String? Function(String songId)? serverFileResolver;
  final Future<bool> Function(String path)? localFileExists;
  final Future<int?> Function(String path)? localFileLength;
  final Future<Uint8List?> Function(String path)? readLocalFileBytes;

  final void Function(PlayerApiClient? client)? onAttachedClientChanged;
  final void Function(PlayerAudioState state)? onAudioStateChanged;
  final Future<String?> Function()? readLegacyDiscoveryApiKey;
  final ({String username, String password})? Function()?
      takePendingLocalSignIn;

  final Widget? Function(
    BuildContext context,
    ConnectionController connection,
  )? setupOverlayBuilder;
  final Widget Function(
    BuildContext context,
    VoidCallback onFinished,
  )? setupCompletionOverlayBuilder;
  final bool Function()? takeSetupJustCompleted;
  final Future<void> Function(BuildContext context)? onSignInResetServer;
  final Stream<DiscoveredLanServer> Function()? discoverLanServers;

  final String? checkUpdateLabel;
  final VoidCallback? onOpenUpdates;
}

T? maybeReadProvider<T>(BuildContext context) {
  try {
    return Provider.of<T>(context, listen: false);
  } on ProviderNotFoundException {
    return null;
  } on ProviderNullException {
    return null;
  }
}

T? maybeWatchProvider<T>(BuildContext context) {
  try {
    return Provider.of<T>(context);
  } on ProviderNotFoundException {
    return null;
  } on ProviderNullException {
    return null;
  }
}

R maybeSelectProvider<T, R>(
  BuildContext context,
  R Function(T value) selector, {
  required R fallback,
}) {
  try {
    return context.select<T, R>(selector);
  } on ProviderNotFoundException {
    return fallback;
  } on ProviderNullException {
    return fallback;
  }
}

PlayerHost? maybeReadHost(BuildContext context) =>
    maybeReadProvider<PlayerHost?>(context) ??
    maybeReadProvider<PlayerHost>(context);
