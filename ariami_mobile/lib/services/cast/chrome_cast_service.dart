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

  bool get isSupportedPlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  bool get isInitialized => _isInitialized;
  bool get isDiscoveryActive => _isDiscoveryActive;
  List<GoogleCastDevice> get devices => List.unmodifiable(_devices);
  String? get connectedDeviceName => _connectedDeviceName;

  GoogleCastConnectState get connectionState =>
      GoogleCastSessionManager.instance.connectionState;

  bool get isConnected => connectionState == GoogleCastConnectState.connected;

  bool get isConnecting => connectionState == GoogleCastConnectState.connecting;
  GoggleCastMediaStatus? get mediaStatus =>
      GoogleCastRemoteMediaClient.instance.mediaStatus;
  Duration get remotePosition =>
      GoogleCastRemoteMediaClient.instance.playerPosition;
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
        notifyListeners();
      });
      _positionSubscription ??=
          GoogleCastRemoteMediaClient.instance.playerPositionStream.listen((_) {
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

    await GoogleCastSessionManager.instance.startSessionWithDevice(device);
    _connectedDeviceName = device.friendlyName;
    notifyListeners();
  }

  Future<void> disconnect() async {
    if (!isSupportedPlatform || !isConnected) return;

    await GoogleCastSessionManager.instance.endSessionAndStopCasting();
    _connectedDeviceName = null;
    _lastCastedSongId = null;
    _lastSentPlaying = null;
    notifyListeners();
  }

  Future<void> play() async {
    if (!isConnected) return;
    await GoogleCastRemoteMediaClient.instance.play();
  }

  Future<void> pause() async {
    if (!isConnected) return;
    await GoogleCastRemoteMediaClient.instance.pause();
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
    if (!isConnected) {
      _connectedDeviceName = null;
      _lastCastedSongId = null;
      _lastSentPlaying = null;
    }
    notifyListeners();
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
