import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';

import '../../models/api_models.dart';
import '../../models/quality_settings.dart';
import '../../models/song.dart';
import '../api/api_client.dart';
import '../api/connection_service.dart';
import '../quality/quality_settings_service.dart';

/// Provides a modular Chromecast integration layer for Ariami mobile.
class ChromeCastService extends ChangeNotifier {
  static final ChromeCastService _instance = ChromeCastService._internal();
  factory ChromeCastService() => _instance;
  ChromeCastService._internal();

  static const String _defaultCastAppId = 'CC1AD845';

  final ConnectionService _connectionService = ConnectionService();
  final QualitySettingsService _qualityService = QualitySettingsService();

  final List<GoogleCastDevice> _devices = [];
  StreamSubscription<List<GoogleCastDevice>>? _devicesSubscription;
  StreamSubscription<dynamic>? _sessionSubscription;
  StreamSubscription<dynamic>? _mediaStatusSubscription;
  StreamSubscription<Duration>? _positionSubscription;

  bool _isInitialized = false;
  bool _isDiscoveryActive = false;
  String? _connectedDeviceName;
  String? _lastCastedSongId;
  bool? _lastSentPlaying;
  bool _isSyncing = false;
  bool _forceLocalPlayback = false;
  Duration _lastKnownRemotePosition = Duration.zero;
  DateTime? _lastRemotePositionUpdatedAt;
  CastMediaPlayerState? _lastRemotePlayerState;

  bool get isSupportedPlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  bool get isInitialized => _isInitialized;
  bool get isDiscoveryActive => _isDiscoveryActive;
  List<GoogleCastDevice> get devices => List.unmodifiable(_devices);
  String? get connectedDeviceName => _connectedDeviceName;

  GoogleCastConnectState get connectionState =>
      GoogleCastSessionManager.instance.connectionState;

  bool get hasActiveSession =>
      connectionState == GoogleCastConnectState.connected;

  bool get isConnected => hasActiveSession && !_forceLocalPlayback;

  bool get isConnecting => connectionState == GoogleCastConnectState.connecting;
  double get deviceVolume =>
      GoogleCastSessionManager.instance.currentSession?.currentDeviceVolume ??
      0.0;
  bool get isDeviceMuted =>
      GoogleCastSessionManager.instance.currentSession?.currentDeviceMuted ??
      false;
  GoggleCastMediaStatus? get mediaStatus =>
      GoogleCastRemoteMediaClient.instance.mediaStatus;
  Duration get rawRemotePosition =>
      GoogleCastRemoteMediaClient.instance.playerPosition;
  Duration get remotePosition => _estimateRemotePosition();
  Duration? get remoteDuration => mediaStatus?.mediaInformation?.duration;

  bool get isRemotePlaying {
    final state = mediaStatus?.playerState;
    return state == CastMediaPlayerState.playing ||
        state == CastMediaPlayerState.buffering ||
        state == CastMediaPlayerState.loading;
  }

  bool get isRemoteBuffering {
    final state = mediaStatus?.playerState;
    return state == CastMediaPlayerState.buffering ||
        state == CastMediaPlayerState.loading;
  }

  Future<void> initialize() async {
    if (_isInitialized || !isSupportedPlatform) {
      return;
    }

    try {
      await _initializeCastContext();

      _devicesSubscription ??=
          GoogleCastDiscoveryManager.instance.devicesStream.listen((devices) {
        _devices
          ..clear()
          ..addAll(devices);
        notifyListeners();
      });

      _sessionSubscription ??=
          GoogleCastSessionManager.instance.currentSessionStream.listen((_) {
        _handleSessionUpdate();
      });
      _mediaStatusSubscription ??=
          GoogleCastRemoteMediaClient.instance.mediaStatusStream.listen((_) {
        _handleMediaStatusChanged();
      });
      _positionSubscription ??= GoogleCastRemoteMediaClient
          .instance.playerPositionStream
          .listen((pos) {
        _recordRemotePosition(pos);
        notifyListeners();
      });

      _isInitialized = true;
      _handleSessionUpdate();
    } catch (e) {
      debugPrint('[ChromeCastService] Failed to initialize: $e');
    }
  }

  Future<void> _initializeCastContext() async {
    final GoogleCastOptions options;

    if (Platform.isIOS) {
      options = IOSGoogleCastOptions(
        GoogleCastDiscoveryCriteriaInitialize.initWithApplicationID(
          _defaultCastAppId,
        ),
        physicalVolumeButtonsWillControlDeviceVolume: true,
        stopCastingOnAppTerminated: true,
      );
    } else {
      options = GoogleCastOptionsAndroid(
        appId: _defaultCastAppId,
        stopCastingOnAppTerminated: true,
      );
    }

    await GoogleCastContext.instance.setSharedInstanceWithOptions(options);
  }

  Future<void> startDiscovery() async {
    if (!isSupportedPlatform) return;
    await initialize();
    if (_isDiscoveryActive) return;

    await GoogleCastDiscoveryManager.instance.startDiscovery();
    _isDiscoveryActive = true;
    notifyListeners();
  }

  Future<void> stopDiscovery() async {
    if (!isSupportedPlatform) return;
    if (!_isDiscoveryActive) return;

    await GoogleCastDiscoveryManager.instance.stopDiscovery();
    _isDiscoveryActive = false;
    notifyListeners();
  }

  Future<void> connectToDevice(GoogleCastDevice device) async {
    if (!isSupportedPlatform) return;
    await initialize();
    _forceLocalPlayback = false;

    final started =
        await GoogleCastSessionManager.instance.startSessionWithDevice(device);
    if (!started) {
      throw StateError('Failed to start Chromecast session.');
    }

    if (!isConnected) {
      await GoogleCastSessionManager.instance.currentSessionStream
          .firstWhere(
            (session) =>
                session?.connectionState == GoogleCastConnectState.connected,
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException(
              'Chromecast connection timed out.',
            ),
          );
    }

    _connectedDeviceName = device.friendlyName;
    notifyListeners();
  }

  Future<void> disconnect() async {
    if (!isSupportedPlatform || !hasActiveSession) return;

    logDebugSnapshot('before-disconnect');
    await GoogleCastSessionManager.instance.endSessionAndStopCasting();
    _connectedDeviceName = null;
    _lastCastedSongId = null;
    _lastSentPlaying = null;
    notifyListeners();
  }

  Future<void> play() async {
    if (!isConnected) return;
    await GoogleCastRemoteMediaClient.instance.play();
    _lastRemotePlayerState = CastMediaPlayerState.playing;
    _lastRemotePositionUpdatedAt = DateTime.now();
  }

  Future<void> pause() async {
    if (!isConnected) return;
    final frozenPosition = _estimateRemotePosition();
    await GoogleCastRemoteMediaClient.instance.pause();
    _recordRemotePosition(frozenPosition);
    _lastRemotePlayerState = CastMediaPlayerState.paused;
  }

  Future<void> seek(Duration position, {required bool playAfterSeek}) async {
    if (!isConnected) return;
    await GoogleCastRemoteMediaClient.instance.seek(
      GoogleCastMediaSeekOption(
        position: position,
        resumeState: playAfterSeek
            ? GoogleCastMediaResumeState.play
            : GoogleCastMediaResumeState.pause,
      ),
    );
    _recordRemotePosition(position);
    _lastRemotePlayerState = playAfterSeek
        ? CastMediaPlayerState.playing
        : CastMediaPlayerState.paused;
  }

  void setDeviceVolume(double value) {
    if (!hasActiveSession) {
      return;
    }

    GoogleCastSessionManager.instance.setDeviceVolume(
      value.clamp(0.0, 1.0).toDouble(),
    );
  }

  /// Syncs the currently playing song to Chromecast when connected.
  /// Returns true when a cast media load request was sent.
  Future<bool> syncFromPlayback({
    required Song? song,
    required Duration position,
    required bool isPlaying,
    bool force = false,
  }) async {
    if (!isConnected || song == null) {
      return false;
    }

    if (_isSyncing) {
      return false;
    }

    if (!force && _lastCastedSongId == song.id) {
      if (_lastSentPlaying != isPlaying) {
        if (isPlaying) {
          await GoogleCastRemoteMediaClient.instance.play();
        } else {
          await GoogleCastRemoteMediaClient.instance.pause();
        }
        _lastSentPlaying = isPlaying;
        return true;
      }
      return false;
    }

    _isSyncing = true;
    try {
      final payload = await _buildPayload(song, position);
      if (payload == null) {
        return false;
      }

      final mediaInfo = GoogleCastMediaInformation(
        contentId: payload.streamUrl,
        contentUrl: Uri.parse(payload.streamUrl),
        streamType: CastMediaStreamType.buffered,
        contentType: payload.contentType,
      );

      await GoogleCastRemoteMediaClient.instance.loadMedia(
        mediaInfo,
        autoPlay: isPlaying,
        playPosition: payload.position,
      );

      _recordRemotePosition(payload.position);
      _lastRemotePlayerState = isPlaying
          ? CastMediaPlayerState.playing
          : CastMediaPlayerState.paused;
      _lastCastedSongId = song.id;
      _lastSentPlaying = isPlaying;
      return true;
    } finally {
      _isSyncing = false;
    }
  }

  Future<_CastPayload?> _buildPayload(Song song, Duration position) async {
    final apiClient = _connectionService.apiClient;
    if (apiClient == null) {
      return null;
    }

    final quality = _qualityService.getCurrentStreamingQuality();
    final streamUrl = await _getStreamUrlWithRetry(
      apiClient: apiClient,
      song: song,
      quality: quality,
    );
    if (streamUrl == null) {
      return null;
    }

    return _CastPayload(
      streamUrl: streamUrl,
      contentType: _resolveContentType(song, quality),
      position: position,
    );
  }

  Future<String?> _getStreamUrlWithRetry({
    required ApiClient apiClient,
    required Song song,
    required StreamingQuality quality,
  }) async {
    if (!_connectionService.isAuthenticated) {
      return apiClient.getStreamUrlWithQuality(song.id, quality);
    }

    final qualityParam =
        quality == StreamingQuality.high ? null : quality.toApiParam();

    try {
      final ticketResponse = await apiClient.getStreamTicket(
        song.id,
        quality: qualityParam,
      );
      return apiClient.getStreamUrlWithToken(
        song.id,
        ticketResponse.streamToken,
        quality: quality,
      );
    } on ApiException catch (e) {
      if (!e.isCode(ApiErrorCodes.streamTokenExpired)) {
        rethrow;
      }

      final retryTicketResponse = await apiClient.getStreamTicket(
        song.id,
        quality: qualityParam,
      );
      return apiClient.getStreamUrlWithToken(
        song.id,
        retryTicketResponse.streamToken,
        quality: quality,
      );
    }
  }

  String _resolveContentType(Song song, StreamingQuality quality) {
    if (quality != StreamingQuality.high) {
      return 'audio/aac';
    }

    final filePath = song.filePath.toLowerCase();
    if (filePath.endsWith('.flac')) return 'audio/flac';
    if (filePath.endsWith('.m4a') || filePath.endsWith('.mp4')) {
      return 'audio/mp4';
    }
    if (filePath.endsWith('.aac')) return 'audio/aac';
    if (filePath.endsWith('.ogg') || filePath.endsWith('.opus')) {
      return 'audio/ogg';
    }
    if (filePath.endsWith('.wav')) return 'audio/wav';
    return 'audio/mpeg';
  }

  void _handleSessionUpdate() {
    if (!hasActiveSession) {
      _connectedDeviceName = null;
      _lastCastedSongId = null;
      _lastSentPlaying = null;
      _forceLocalPlayback = false;
      _lastKnownRemotePosition = Duration.zero;
      _lastRemotePositionUpdatedAt = null;
      _lastRemotePlayerState = null;
    }
    notifyListeners();
  }

  Future<void> beginLocalPlaybackHandoff({
    required Duration capturedPosition,
    required bool wasPlaying,
  }) async {
    if (!hasActiveSession) {
      return;
    }

    _recordRemotePosition(capturedPosition);
    _lastRemotePlayerState =
        wasPlaying ? CastMediaPlayerState.playing : CastMediaPlayerState.paused;
    _forceLocalPlayback = true;
    notifyListeners();

    if (!wasPlaying) {
      return;
    }

    try {
      await GoogleCastRemoteMediaClient.instance
          .pause()
          .timeout(const Duration(milliseconds: 750));
      _recordRemotePosition(capturedPosition);
      _lastRemotePlayerState = CastMediaPlayerState.paused;
      debugPrint(
        '[ChromeCastService][local-handoff] remote pause acknowledged',
      );
    } on TimeoutException {
      debugPrint(
        '[ChromeCastService][local-handoff] remote pause timed out, continuing',
      );
    } catch (e) {
      debugPrint(
        '[ChromeCastService][local-handoff] remote pause failed: $e',
      );
    }
  }

  void disconnectInBackground() {
    if (!hasActiveSession) {
      return;
    }

    unawaited(() async {
      try {
        await disconnect().timeout(const Duration(seconds: 5));
        debugPrint(
          '[ChromeCastService][background-disconnect] disconnect completed',
        );
      } on TimeoutException {
        debugPrint(
          '[ChromeCastService][background-disconnect] disconnect timed out',
        );
      } catch (e) {
        debugPrint(
          '[ChromeCastService][background-disconnect] disconnect failed: $e',
        );
      }
    }());
  }

  void _handleMediaStatusChanged() {
    final now = DateTime.now();
    final nextState = mediaStatus?.playerState;
    final wasAdvancing = _isAdvancingState(_lastRemotePlayerState);
    final isAdvancing = _isAdvancingState(nextState);

    if (wasAdvancing && !isAdvancing) {
      _recordRemotePosition(_estimateRemotePosition(now: now), at: now);
    } else if (!wasAdvancing && isAdvancing) {
      _lastRemotePositionUpdatedAt = now;
    }

    _lastRemotePlayerState = nextState;
    notifyListeners();
  }

  bool _isAdvancingState(CastMediaPlayerState? state) {
    return state == CastMediaPlayerState.playing ||
        state == CastMediaPlayerState.buffering ||
        state == CastMediaPlayerState.loading;
  }

  void _recordRemotePosition(Duration position, {DateTime? at}) {
    _lastKnownRemotePosition =
        position < Duration.zero ? Duration.zero : position;
    _lastRemotePositionUpdatedAt = at ?? DateTime.now();
  }

  Duration _estimateRemotePosition({DateTime? now}) {
    var position = _lastKnownRemotePosition;
    final capturedAt = _lastRemotePositionUpdatedAt;
    final effectiveNow = now ?? DateTime.now();

    if (_isAdvancingState(mediaStatus?.playerState) && capturedAt != null) {
      position += effectiveNow.difference(capturedAt);
    }

    final duration = remoteDuration;
    if (duration != null && duration > Duration.zero && position > duration) {
      return duration;
    }

    return position < Duration.zero ? Duration.zero : position;
  }

  void logDebugSnapshot(String label) {
    final status = mediaStatus;
    final now = DateTime.now();
    debugPrint(
      '[ChromeCastService][$label] '
      'connected=$isConnected '
      'state=${status?.playerState} '
      'raw=${rawRemotePosition.inMilliseconds}ms '
      'estimated=${_estimateRemotePosition(now: now).inMilliseconds}ms '
      'lastKnown=${_lastKnownRemotePosition.inMilliseconds}ms '
      'lastUpdateAt=${_lastRemotePositionUpdatedAt?.toIso8601String()} '
      'duration=${remoteDuration?.inMilliseconds}ms '
      'songId=$_lastCastedSongId',
    );
  }
}

class _CastPayload {
  final String streamUrl;
  final String contentType;
  final Duration position;

  const _CastPayload({
    required this.streamUrl,
    required this.contentType,
    required this.position,
  });
}
