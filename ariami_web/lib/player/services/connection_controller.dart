import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/player_models.dart';
import 'player_api_client.dart';
import 'player_host.dart';

enum ConnectionStage {
  /// Restoring the last target and saved session before showing any auth UI.
  initializing,

  /// No server chosen yet.
  idle,

  /// Reaching out to a server (`/server-info`).
  connecting,

  /// Server reachable but the user must sign in.
  needsAuth,

  /// The invite was accepted as a pairing attempt and an account is needed.
  needsRegistration,

  /// Fully connected and authenticated; library can load.
  connected,

  /// Was connected, but the server stopped responding.
  ///
  /// Session, client, and server metadata are kept so the controller can retry
  /// without asking the user to sign in again. The player keeps running in
  /// automatic offline mode (downloaded music) while retries continue.
  reconnecting,

  /// The user explicitly chose offline mode: no reconnect attempts run until
  /// [ConnectionController.goOnline] is called. Persisted across launches.
  offline,

  /// Something failed; [ConnectionController.errorMessage] explains.
  error,
}

/// The account flow selected after entering a server and pairing code.
enum PairingAction {
  login,
  register,
}

class ConnectionController extends ChangeNotifier {
  ConnectionController({PlayerHost? host})
      : _host = host,
        _tokenStore = host?.sessionTokenStore ?? PrefsSessionTokenStore(),
        _deviceIdPrefix = host?.deviceIdPrefix ?? 'web_client_',
        _deviceName = host?.apiDeviceName ?? 'Ariami Web',
        _connectDeviceName = host?.defaultDeviceName ?? 'Ariami Web',
        _platformLabel = host?.platformLabel ?? 'web',
        _sameOriginUri = host?.sameOriginUri;

  static const _deviceIdKey = 'player_device_id';
  static const _lastSchemeKey = 'player_last_scheme';
  static const _lastHostKey = 'player_last_host';
  static const _lastPortKey = 'player_last_port';
  static const _lastTargetKey = 'player_last_target';
  static const _lastLanKey = 'player_last_lan';
  static const _lastTailscaleKey = 'player_last_tailscale';
  static const _sessionTokenKeyPrefix = 'player_session_token_';
  static const _lastUsernameKey = 'player_last_username';
  static const _manualOfflineKey = 'player_manual_offline_v1';
  static const _remoteTarget = 'remote';
  static const _localTarget = 'local';

  /// The embedded server (server + client mode) always listens on loopback.
  static const _localHost = '127.0.0.1';

  final PlayerHost? _host;
  final SessionTokenStore _tokenStore;
  final String _deviceIdPrefix;
  final String _deviceName;
  final String _connectDeviceName;
  final String _platformLabel;
  final Uri? _sameOriginUri;

  ConnectionStage _stage = ConnectionStage.initializing;
  ConnectionStage get stage => _stage;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  PlayerServerInfo? _serverInfo;
  PlayerServerInfo? get serverInfo => _serverInfo;

  PlayerApiClient? _client;
  PlayerApiClient? get client => _client;

  String? _username;
  String? get username => _username;

  Uint8List? _avatarBytes;
  Uint8List? get avatarBytes => _avatarBytes;

  int? _avatarUpdatedAt;

  /// Set when a sign-in is rejected because the account is active elsewhere;
  /// the UI offers a "take over" retry.
  bool _needsTakeoverConfirmation = false;
  bool get needsTakeoverConfirmation => _needsTakeoverConfirmation;

  String? _deviceId;
  String? _lastUsername;
  String? get lastUsername => _lastUsername;

  String? _pairingCode;
  String _pendingScheme = 'http';
  String? _pendingHost;
  int _pendingPort = 8080;

  /// Whether the active connection is the embedded local server or a remote
  /// one — controls how the session is persisted for [autoConnect].
  String _currentTarget = _remoteTarget;

  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  Timer? _launchRetryTimer;
  Timer? _wakeWatchTimer;
  DateTime _lastWakeWatchTick = DateTime.now();

  /// Upper bound for one reconnect attempt. Every network call inside has its
  /// own timeout, but a hung await (e.g. a keychain write right after wake)
  /// must never leave the in-flight flag set, or no retry would ever run again.
  static const _attemptWatchdog = Duration(seconds: 30);
  bool _isConnectivityCheckInFlight = false;
  bool _isRefreshingAccount = false;
  bool _isDisconnecting = false;
  bool _isDisposed = false;
  String get pendingScheme => _pendingScheme;
  String? get pendingHost => _pendingHost;
  int get pendingPort => _pendingPort;
  bool get hasPendingPairingCode => _pairingCode != null;
  bool get isReconnectionAttemptInFlight =>
      _stage == ConnectionStage.reconnecting && _isConnectivityCheckInFlight;

  String? get reconnectingAddress {
    final host = _serverInfo?.host ?? _pendingHost;
    final port = _serverInfo?.port ?? _pendingPort;
    if (host == null || host.isEmpty) return null;
    return '$host:$port';
  }

  /// True while connected to (or connecting to) the embedded local server.
  bool get isLocalServer => _currentTarget == _localTarget;

  /// True when hosted on an explicit/same-origin web URL.
  bool get isSameOriginWeb => _sameOriginUri != null;

  /// Only standalone remote-player flows allow discarding the current server
  /// and pairing with another address.
  bool get canChooseDifferentServer => !isLocalServer && !isSameOriginWeb;

  bool get canGoOffline =>
      !isLocalServer && !isSameOriginWeb && _host?.downloads != null;

  bool get isConnected => _stage == ConnectionStage.connected;

  /// True while the app should run against downloaded music: either the user
  /// chose offline mode, or the server is unreachable and we're auto-retrying.
  bool get isOfflineActive =>
      _stage == ConnectionStage.offline ||
      _stage == ConnectionStage.reconnecting;

  /// True only for the user-chosen (persisted) offline mode.
  bool get isManualOffline => _stage == ConnectionStage.offline;

  /// Stable identity and credentials used by the dedicated Connect socket.
  Future<String> get connectDeviceId => _ensureDeviceId();
  String get connectDeviceName => _connectDeviceName;
  String? get connectSessionToken => _client?.sessionToken;
  String? get connectBaseUrl => _serverInfo?.baseUrl;

  Future<String> _ensureDeviceId() async {
    if (_deviceId != null) return _deviceId!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceIdKey);
    if (id == null || id.isEmpty) {
      id = '$_deviceIdPrefix${const Uuid().v4()}';
      await prefs.setString(_deviceIdKey, id);
    }
    _deviceId = id;
    return id;
  }

  void _setStage(ConnectionStage stage, {String? error}) {
    if (_isDisposed) return;
    _stage = stage;
    _errorMessage = error;
    notifyListeners();
  }

  /// Connects to a remote server by host/port.
  ///
  /// [knownLan]/[knownTailscale] are the endpoints learned on a previous
  /// connection (from `/server-info`); supplying them lets a reconnect reach
  /// the server after the device has moved between the LAN and Tailscale.
  ///
  /// With [offlineFallbackOnFailure], a network failure enters the
  /// auto-offline reconnecting state (retrying in the background) instead of
  /// the error screen — used when restoring a previous session at launch, so
  /// an unreachable server still lets the user play downloaded music.
  Future<void> connectSameOrigin(Uri origin) async {
    _currentTarget = _remoteTarget;
    final scheme = origin.scheme.isEmpty ? 'http' : origin.scheme;
    final host = origin.host;
    final port = origin.hasPort ? origin.port : (scheme == 'https' ? 443 : 80);
    _pendingScheme = scheme;
    _pendingHost = host;
    _pendingPort = port;
    _setStage(ConnectionStage.connecting);
    try {
      await _connectTo(
        scheme: scheme,
        host: host,
        port: port,
        sameOriginOnly: true,
      );
    } on PlayerApiException catch (e) {
      _setStage(ConnectionStage.error, error: e.message);
    } catch (e) {
      _setStage(ConnectionStage.error, error: 'Failed to connect: $e');
    }
  }

  Future<void> connectRemote(
    String host,
    int port, {
    String scheme = 'http',
    String? knownLan,
    String? knownTailscale,
    bool offlineFallbackOnFailure = false,
  }) async {
    _currentTarget = _remoteTarget;
    _pendingScheme = scheme;
    _pendingHost = host;
    _pendingPort = port;
    _setStage(ConnectionStage.connecting);
    try {
      await _connectTo(
        scheme: scheme,
        host: host,
        port: port,
        knownLan: knownLan,
        knownTailscale: knownTailscale,
      );
    } on PlayerApiException catch (e) {
      if (offlineFallbackOnFailure && e.code == 'NETWORK_ERROR') {
        _enterLaunchOfflineRetry();
        return;
      }
      _setStage(ConnectionStage.error, error: e.message);
    } catch (e) {
      _setStage(ConnectionStage.error, error: 'Failed to connect: $e');
    }
  }

  /// Enters manual offline mode: reconnect attempts stop and the choice is
  /// persisted, so the app launches straight into offline until [goOnline].
  /// Not available in server + player mode (the server is this machine).
  Future<void> goOffline() async {
    if (!canGoOffline || _stage == ConnectionStage.offline) return;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _launchRetryTimer?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_manualOfflineKey, true);
    _setStage(ConnectionStage.offline);
  }

  /// Leaves manual offline mode and starts reconnecting (background retries,
  /// so failure keeps the player usable in auto-offline instead of erroring).
  Future<void> goOnline() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_manualOfflineKey);
    if (_stage != ConnectionStage.offline) return;
    if (_client != null && _serverInfo != null) {
      _stage = ConnectionStage.reconnecting;
      notifyListeners();
      _startReconnectTimer();
      unawaited(_checkConnectivity());
      return;
    }
    final host = _pendingHost ?? prefs.getString(_lastHostKey);
    final port = prefs.getInt(_lastPortKey) ?? _pendingPort;
    final scheme = prefs.getString(_lastSchemeKey) ?? _pendingScheme;
    if (host != null && host.isNotEmpty) {
      await connectRemote(
        host,
        port,
        scheme: scheme,
        knownLan: prefs.getString(_lastLanKey),
        knownTailscale: prefs.getString(_lastTailscaleKey),
        offlineFallbackOnFailure: true,
      );
      return;
    }
    _setStage(ConnectionStage.idle);
  }

  /// Auto-offline at launch: show the offline player and quietly retry the
  /// saved server until it answers. Deliberately does not flap through the
  /// `connecting` stage, so the offline UI stays put between attempts.
  void _enterLaunchOfflineRetry() {
    _setStage(ConnectionStage.reconnecting);
    _startWakeWatch();
    _launchRetryTimer?.cancel();
    _launchRetryTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_stage != ConnectionStage.reconnecting) {
        _launchRetryTimer?.cancel();
        return;
      }
      unawaited(_reconnectFromSaved());
    });
  }

  /// Resolves the saved server from scratch, exactly as a launch does: the
  /// typed host plus the LAN/Tailscale endpoints learned last time. Used while
  /// reconnecting without an authenticated client (unreachable at launch).
  Future<void> _reconnectFromSaved() async {
    if (_stage != ConnectionStage.reconnecting ||
        _isConnectivityCheckInFlight ||
        _isDisposed) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final host = _pendingHost ?? prefs.getString(_lastHostKey);
    if (host == null || host.isEmpty) return;
    _setCheckInFlight(true);
    try {
      await _connectTo(
        scheme: prefs.getString(_lastSchemeKey) ?? _pendingScheme,
        host: host,
        port: prefs.getInt(_lastPortKey) ?? _pendingPort,
        knownLan: prefs.getString(_lastLanKey),
        knownTailscale: prefs.getString(_lastTailscaleKey),
      ).timeout(_attemptWatchdog);
      _launchRetryTimer?.cancel();
    } catch (e) {
      debugPrint('[Connection] Saved-server reconnect failed: $e');
    } finally {
      _setCheckInFlight(false);
    }
  }

  /// Flips the in-flight flag and, while reconnecting, tells the offline
  /// banner so its "Reconnecting…" state appears the moment an attempt starts.
  void _setCheckInFlight(bool value) {
    _isConnectivityCheckInFlight = value;
    if (!_isDisposed && _stage == ConnectionStage.reconnecting) {
      notifyListeners();
    }
  }

  Future<void> connectLocal({
    required int port,
    String? initialUsername,
    String? initialPassword,
  }) async {
    _currentTarget = _localTarget;
    _pendingHost = _localHost;
    _pendingPort = port;
    _setStage(ConnectionStage.connecting);
    try {
      await _connectTo(
        host: _localHost,
        port: port,
        isLocal: true,
        initialUsername: initialUsername,
        initialPassword: initialPassword,
      );
    } on PlayerApiException catch (e) {
      _setStage(ConnectionStage.error, error: e.message);
    } catch (e) {
      _setStage(ConnectionStage.error, error: 'Failed to connect: $e');
    }
  }

  /// Connects to a server using an optional owner-issued invite code.
  /// An 8-character invite code is required only for [PairingAction.register].
  Future<void> pairWithServer(
    String host,
    int port,
    String inviteCode, {
    String scheme = 'http',
    required PairingAction action,
  }) async {
    _currentTarget = _remoteTarget;
    _pendingScheme = scheme;
    _pendingHost = host;
    _pendingPort = port;
    final normalizedCode =
        inviteCode.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (action == PairingAction.register && normalizedCode.length != 8) {
      _setStage(
        ConnectionStage.error,
        error: 'Enter the 8-character invite code shown by the server owner.',
      );
      return;
    }
    _pairingCode = normalizedCode.length == 8 ? normalizedCode : null;
    _setStage(ConnectionStage.connecting);

    try {
      await _prepareRemoteClient(scheme: scheme, host: host, port: port);
      _setStage(
        action == PairingAction.login
            ? ConnectionStage.needsAuth
            : ConnectionStage.needsRegistration,
      );
    } on PlayerApiException catch (e) {
      _setStage(ConnectionStage.error, error: e.message);
    } catch (e) {
      _setStage(ConnectionStage.error, error: 'Failed to connect: $e');
    }
  }

  void showSignIn() {
    if (_client == null) return;
    _needsTakeoverConfirmation = false;
    _setStage(ConnectionStage.needsAuth);
  }

  /// Registration is only available while a pairing code is pending.
  void showRegistration() {
    if (_client == null || _pairingCode == null) return;
    _needsTakeoverConfirmation = false;
    _setStage(ConnectionStage.needsRegistration);
  }

  Future<void> _connectTo({
    String scheme = 'http',
    required String host,
    required int port,
    String? knownLan,
    String? knownTailscale,
    bool isLocal = false,
    bool sameOriginOnly = false,
    String? initialUsername,
    String? initialPassword,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await _prepareRemoteClient(
      scheme: scheme,
      host: host,
      port: port,
      knownLan: knownLan,
      knownTailscale: knownTailscale,
      isLocal: isLocal,
      sameOriginOnly: sameOriginOnly,
    );
    final info = _serverInfo!;

    if (!sameOriginOnly) {
      await _persistTarget(prefs, info, typedHost: host);
    }
    _lastUsername = prefs.getString(_lastUsernameKey);

    if (!info.authRequired) {
      _finishConnection();
      return;
    }

    // Try a stored session token for this server first. Keyed by a stable id
    // (not the active host) so it survives LAN/Tailscale endpoint switches.
    final storedToken = await _storedSessionToken(prefs, info);
    if (storedToken != null && storedToken.isNotEmpty) {
      _client!.sessionToken = storedToken;
      final validFuture = _validateSession();
      final connectFuture = _client!.connectClient(platform: _platformLabel);
      connectFuture.ignore();
      if (await validFuture) {
        _username = _lastUsername;
        await connectFuture;
        _finishConnection();
        return;
      }
      _client!.sessionToken = null;
    }

    if (initialUsername != null &&
        initialUsername.trim().isNotEmpty &&
        initialPassword != null &&
        initialPassword.isNotEmpty) {
      await signIn(initialUsername, initialPassword);
      return;
    }

    _setStage(ConnectionStage.needsAuth);
  }

  /// Persist the active connection target and the LAN/Tailscale endpoints
  /// advertised by [info], so [autoConnect] can re-resolve next launch.
  Future<void> _persistTarget(
    SharedPreferences prefs,
    PlayerServerInfo info, {
    required String typedHost,
  }) async {
    await _setOrRemove(prefs, _lastTargetKey, _currentTarget);
    await _setOrRemove(prefs, _lastSchemeKey, info.scheme);
    await _setOrRemove(prefs, _lastHostKey, typedHost);
    if (prefs.getInt(_lastPortKey) != info.port) {
      await prefs.setInt(_lastPortKey, info.port);
    }
    await _setOrRemove(prefs, _lastLanKey, info.lanServer);
    await _setOrRemove(prefs, _lastTailscaleKey, info.tailscaleServer);
  }

  Future<void> _setOrRemove(
    SharedPreferences prefs,
    String key,
    String? value,
  ) async {
    if (value == null || value.isEmpty) {
      if (prefs.containsKey(key)) await prefs.remove(key);
    } else if (prefs.getString(key) != value) {
      await prefs.setString(key, value);
    }
  }

  Future<void> _prepareRemoteClient({
    String scheme = 'http',
    required String host,
    required int port,
    String? knownLan,
    String? knownTailscale,
    bool isLocal = false,
    bool sameOriginOnly = false,
  }) async {
    final deviceId = await _ensureDeviceId();

    // Probe the Ariami endpoint itself rather than merely checking whether a
    // TCP port is open. A stale LAN address can host an unrelated service; in
    // that case we must continue to the saved Tailscale address.
    final candidates = (isLocal || sameOriginOnly)
        ? <String>[host]
        : <String>[
            if (knownLan != null) knownLan,
            host,
            if (knownTailscale != null) knownTailscale,
          ];
    final probedHosts = <String>{
      for (final candidate in candidates)
        if (candidate.trim().isNotEmpty) candidate.trim(),
    };
    var result = await _firstAriamiEndpoint(
      probedHosts,
      port,
      scheme: scheme,
      deviceId: deviceId,
    );
    if (result == null) {
      throw PlayerApiException(
        'NETWORK_ERROR',
        'Could not reach an Ariami server at $host:$port. Check that both '
            'devices are on the same LAN or Tailscale network.',
      );
    }

    // Match mobile: prefer the advertised LAN route while it is genuinely an
    // Ariami server. If it is unavailable (or was already probed above), retain
    // the endpoint that already succeeded instead of re-waiting on a dead LAN.
    final lan = result.info.lanServer?.trim();
    if (!isLocal &&
        !sameOriginOnly &&
        lan != null &&
        lan.isNotEmpty &&
        lan != result.host &&
        !probedHosts.contains(lan)) {
      final lanResult = await _firstAriamiEndpoint(
        <String>[lan],
        port,
        scheme: scheme,
        deviceId: deviceId,
        probeTimeout: const Duration(milliseconds: 600),
      );
      if (lanResult != null) {
        result.client.dispose();
        result = lanResult;
      }
    }

    _serverInfo = result.info.copyWith(
      scheme: scheme,
      host: result.host,
      port: port,
    );
    _client?.dispose();
    _client = result.client..timeout = const Duration(seconds: 12);
    _wireClientCallbacks(_client!);
  }

  /// Grace window given to a higher-priority endpoint (e.g. LAN) once a
  /// lower-priority fallback (e.g. Tailscale) has already answered. Local LAN
  /// round-trips complete in a few milliseconds, so 150ms is plenty for a live
  /// LAN route to win without stalling cold starts on a dead LAN timeout.
  static const _preferredEndpointGrace = Duration(milliseconds: 150);

  Future<_EndpointProbe?> _firstAriamiEndpoint(
    Iterable<String> candidates,
    int port, {
    String scheme = 'http',
    required String deviceId,
    String? sessionToken,
    Duration probeTimeout = const Duration(seconds: 3),
  }) async {
    // Probe candidates concurrently, resolving as soon as the highest-priority
    // reachable route answers (or after a short grace window for earlier
    // candidates) instead of waiting for every dead route to time out.
    final hosts = <String>{
      for (final candidate in candidates)
        if (candidate.trim().isNotEmpty) candidate.trim(),
    }.toList(growable: false);
    if (hosts.isEmpty) return null;

    final completer = Completer<_EndpointProbe?>();
    final results = List<_EndpointProbe?>.filled(hosts.length, null);
    final settled = List<bool>.filled(hosts.length, false);
    final clients = List<PlayerApiClient?>.filled(hosts.length, null);
    Timer? graceTimer;

    void finish(_EndpointProbe? chosen) {
      if (completer.isCompleted) return;
      graceTimer?.cancel();
      for (var i = 0; i < clients.length; i++) {
        final client = clients[i];
        if (client != null && !identical(client, chosen?.client)) {
          client.dispose();
        }
      }
      completer.complete(chosen);
    }

    void evaluate() {
      if (completer.isCompleted) return;
      final winnerIndex = results.indexWhere((probe) => probe != null);
      if (winnerIndex != -1) {
        final higherPrioritySettled =
            settled.take(winnerIndex).every((isSettled) => isSettled);
        if (higherPrioritySettled) {
          finish(results[winnerIndex]);
          return;
        }
        graceTimer ??= Timer(_preferredEndpointGrace, () {
          final bestIndex = results.indexWhere((probe) => probe != null);
          finish(bestIndex == -1 ? null : results[bestIndex]);
        });
        return;
      }
      if (settled.every((isSettled) => isSettled)) {
        finish(null);
      }
    }

    for (var i = 0; i < hosts.length; i++) {
      final host = hosts[i];
      final client = PlayerApiClient(
        baseUrl: PlayerServerInfo(
          scheme: scheme,
          host: host,
          port: port,
          name: '',
          version: '',
        ).baseUrl,
        deviceId: deviceId,
        deviceName: _deviceName,
        sessionToken: sessionToken,
        timeout: probeTimeout,
      );
      clients[i] = client;
      unawaited(() async {
        try {
          final info = (await client.fetchServerInfo(host, scheme: scheme))
              .copyWith(scheme: scheme, port: port);
          if (completer.isCompleted) {
            client.dispose();
            return;
          }
          results[i] = _EndpointProbe(host: host, info: info, client: client);
        } catch (_) {
          client.dispose();
          clients[i] = null;
        } finally {
          settled[i] = true;
          evaluate();
        }
      }());
    }

    return completer.future;
  }

  Future<String?> _storedSessionToken(
    SharedPreferences prefs,
    PlayerServerInfo info,
  ) async {
    for (final alias in <String>{info.stableKey, ...info.endpointAliases}) {
      final token = await _tokenStore.read(
        '$_sessionTokenKeyPrefix$alias',
        legacyPrefs: prefs,
      );
      if (token != null && token.isNotEmpty) return token;
    }
    return null;
  }

  /// Creates an account with the pairing code, then completes a normal mobile
  /// login and client-presence handshake.
  Future<void> register(String username, String password) async {
    final client = _client;
    final code = _pairingCode;
    if (client == null || code == null || _serverInfo == null) {
      _setStage(ConnectionStage.error, error: 'Start pairing again.');
      return;
    }

    _setStage(ConnectionStage.connecting);
    var accountCreated = false;
    try {
      await client.register(username, password, code);
      accountCreated = true;
      _pairingCode = null;
      final session = await client.login(username, password);
      await _persistAuthenticatedSession(session);
      await client.connectClient(platform: _platformLabel);
      _finishConnection();
    } on PlayerApiException catch (e) {
      if (accountCreated) {
        _setStage(
          ConnectionStage.needsAuth,
          error: 'Your account was created, but the connection could not be '
              'completed. Sign in to try again.',
        );
        return;
      }
      final invalidCode = e.code == 'REGISTRATION_CLOSED' ||
          e.code == 'REGISTRATION_DISABLED' ||
          e.code == 'PUBLIC_REGISTRATION_DISABLED';
      _setStage(
        ConnectionStage.needsRegistration,
        error: invalidCode
            ? 'That pairing code is invalid or expired. Ask the server owner '
                'for a new code.'
            : e.message,
      );
    } catch (e) {
      if (accountCreated) {
        _setStage(
          ConnectionStage.needsAuth,
          error: 'Your account was created, but the connection could not be '
              'completed. Sign in to try again.',
        );
        return;
      }
      _setStage(
        ConnectionStage.needsRegistration,
        error: 'Could not create the account: $e',
      );
    }
  }

  Future<bool> _validateSession() async {
    final client = _client;
    if (client == null || client.sessionToken == null) return false;
    try {
      await client.checkSession();
      return true;
    } on PlayerApiException catch (e) {
      // Auth errors mean the token is dead; anything else means it worked.
      return !e.isAuthError;
    } catch (_) {
      return false;
    }
  }

  Future<void> signIn(
    String username,
    String password, {
    bool takeOver = false,
  }) async {
    final client = _client;
    if (client == null) {
      _setStage(ConnectionStage.error, error: 'Not connected to a server.');
      return;
    }
    _needsTakeoverConfirmation = false;
    _setStage(ConnectionStage.connecting);
    try {
      final session = await client.login(
        username,
        password,
        allowOtherDeviceTakeover: takeOver,
      );
      await client.connectClient(platform: _platformLabel);
      await _persistAuthenticatedSession(session);
      _finishConnection();
    } on PlayerApiException catch (e) {
      if (e.isAlreadyLoggedInElsewhere) {
        _needsTakeoverConfirmation = true;
        _setStage(
          ConnectionStage.needsAuth,
          error: 'This account is signed in on another device.',
        );
        return;
      }
      _setStage(ConnectionStage.needsAuth, error: e.message);
    } catch (e) {
      _setStage(ConnectionStage.needsAuth, error: 'Sign-in failed: $e');
    }
  }

  Future<void> _persistAuthenticatedSession(AuthSession session) async {
    _username = session.username;
    final prefs = await SharedPreferences.getInstance();
    final info = _serverInfo!;
    for (final alias in <String>{info.stableKey, ...info.endpointAliases}) {
      await _tokenStore.write(
        '$_sessionTokenKeyPrefix$alias',
        session.sessionToken,
        legacyPrefs: prefs,
      );
    }
    await prefs.setString(_lastUsernameKey, session.username);
    if (!isSameOriginWeb) {
      await _persistTarget(prefs, info, typedHost: _pendingHost ?? info.host);
    }
    _lastUsername = session.username;
  }

  void _handleSessionExpired() {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _client?.sessionToken = null;
    _clearAvatar();
    _setStage(
      ConnectionStage.needsAuth,
      error: 'Your session expired. Please sign in again.',
    );
  }

  /// Routes a terminal authentication failure from the dedicated Connect
  /// socket through the same recovery used by authenticated HTTP requests.
  void requireSignIn() => _handleSessionExpired();

  void _handleNetworkError() {
    if (_isDisconnecting ||
        _isDisposed ||
        _isConnectivityCheckInFlight ||
        _stage != ConnectionStage.connected) {
      return;
    }
    unawaited(_checkConnectivity());
  }

  void _wireClientCallbacks(PlayerApiClient client) {
    client.onSessionExpired = _handleSessionExpired;
    client.onNetworkError = _handleNetworkError;
  }

  void _finishConnection() {
    _pairingCode = null;
    _reconnectTimer?.cancel();
    _launchRetryTimer?.cancel();
    _setStage(ConnectionStage.connected);
    _startWakeWatch();
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_stage == ConnectionStage.connected) {
        // Every API request carries the device identity, so ping also refreshes
        // the server's mobile-client presence timestamp.
        unawaited(_heartbeat());
      }
    });
    unawaited(_heartbeat());
    unawaited(refreshAccount());
  }

  Future<void> _heartbeat() async {
    await _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    if (_isConnectivityCheckInFlight ||
        _isDisposed ||
        (_stage != ConnectionStage.connected &&
            _stage != ConnectionStage.reconnecting)) {
      return;
    }
    final client = _client;
    if (client == null) return;

    _setCheckInFlight(true);
    try {
      if (_stage == ConnectionStage.connected && await client.ping()) {
        if (!_isDisposed && identical(client, _client)) notifyListeners();
        unawaited(refreshAccount());
        return;
      }
      final recovered =
          await _recoverEndpoint().timeout(_attemptWatchdog, onTimeout: () {
        debugPrint('[Connection] Endpoint recovery timed out');
        return false;
      });
      if (!recovered) {
        debugPrint('[Connection] Server unreachable (stage: $_stage)');
        if (_stage == ConnectionStage.connected) _enterReconnecting();
      }
    } finally {
      _setCheckInFlight(false);
    }
  }

  void _enterReconnecting() {
    if (_stage != ConnectionStage.connected) return;
    _heartbeatTimer?.cancel();
    _setStage(ConnectionStage.reconnecting);
    _startReconnectTimer();
  }

  void _startReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_stage == ConnectionStage.reconnecting) {
        unawaited(_checkConnectivity());
      }
    });
  }

  /// The banner's "Retry now". Without an authenticated client (the server
  /// was unreachable at launch) this re-resolves the saved endpoints from
  /// scratch; otherwise it re-probes LAN/Tailscale keeping the session.
  Future<void> retryReconnectNow() async {
    if (_stage != ConnectionStage.reconnecting) return;
    if (_client?.sessionToken == null) {
      await _reconnectFromSaved();
    } else {
      await _checkConnectivity();
    }
  }

  /// Closing a laptop lid freezes every timer, so the controller cannot see
  /// the network change underneath it. A wall-clock gap between ticks of this
  /// cheap watcher means the machine slept: check the server right away
  /// instead of waiting for the next heartbeat or retry tick.
  void _startWakeWatch() {
    _lastWakeWatchTick = DateTime.now();
    _wakeWatchTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      final now = DateTime.now();
      final slept =
          now.difference(_lastWakeWatchTick) > const Duration(seconds: 20);
      _lastWakeWatchTick = now;
      if (!slept) return;
      debugPrint('[Connection] Woke from sleep (stage: $_stage)');
      if (_stage == ConnectionStage.connected) {
        unawaited(_checkConnectivity());
      } else {
        unawaited(retryReconnectNow());
      }
    });
  }

  /// Refreshes `/api/me` and updates cached avatar bytes when the server says
  /// the signed-in account's avatar changed.
  Future<void> refreshAccount() async {
    if (_isRefreshingAccount) return;
    final client = _client;
    if (client == null || client.sessionToken == null) return;

    _isRefreshingAccount = true;
    final oldUsername = _username;
    final oldAvatar = _avatarBytes;
    final oldAvatarUpdatedAt = _avatarUpdatedAt;
    try {
      final account = await client.fetchMe();
      if (!identical(client, _client) || _stage != ConnectionStage.connected) {
        return;
      }
      final accountUsername = account.username.trim();
      if (accountUsername.isNotEmpty) {
        _username = accountUsername;
      }

      if (!account.hasAvatar) {
        _clearAvatar();
      } else if (_avatarBytes == null ||
          _avatarUpdatedAt != account.avatarUpdatedAt) {
        try {
          final bytes = await client.fetchMyAvatar();
          if (!identical(client, _client) ||
              _stage != ConnectionStage.connected) {
            return;
          }
          _avatarBytes = bytes == null || bytes.isEmpty ? null : bytes;
          _avatarUpdatedAt =
              _avatarBytes == null ? null : account.avatarUpdatedAt;
        } catch (_) {
          _clearAvatar();
        }
      }
    } catch (_) {
      // Account metadata is supplemental; keep the connection alive if a
      // refresh fails for reasons other than auth expiry.
    } finally {
      _isRefreshingAccount = false;
    }

    if (_username != oldUsername ||
        !identical(_avatarBytes, oldAvatar) ||
        _avatarUpdatedAt != oldAvatarUpdatedAt) {
      notifyListeners();
    }
  }

  void _clearAvatar() {
    _avatarBytes = null;
    _avatarUpdatedAt = null;
  }

  /// Re-resolve LAN/Tailscale while the app is running, as mobile does. The
  /// existing session token moves with the client so an endpoint switch does
  /// not force another sign-in.
  Future<bool> _recoverEndpoint() async {
    if (_stage != ConnectionStage.connected &&
        _stage != ConnectionStage.reconnecting) {
      return false;
    }
    final currentInfo = _serverInfo;
    final currentClient = _client;
    if (currentInfo == null || currentClient == null) return false;

    final deviceId = await _ensureDeviceId();
    final result = await _firstAriamiEndpoint(
      isSameOriginWeb
          ? <String>[currentInfo.host]
          : <String>[
              currentInfo.host,
              if (currentInfo.lanServer != null) currentInfo.lanServer!,
              if (currentInfo.tailscaleServer != null)
                currentInfo.tailscaleServer!,
              if (_pendingHost != null) _pendingHost!,
            ],
      currentInfo.port,
      scheme: currentInfo.scheme,
      deviceId: deviceId,
      sessionToken: currentClient.sessionToken,
    );
    if (result == null) return false;

    final oldClient = _client;
    _serverInfo = result.info.copyWith(
      scheme: currentInfo.scheme,
      host: result.host,
      port: currentInfo.port,
    );
    _client = result.client..timeout = const Duration(seconds: 12);
    _wireClientCallbacks(_client!);
    try {
      await _client!.connectClient(platform: _platformLabel);
      final prefs = await SharedPreferences.getInstance();
      if (!isSameOriginWeb) {
        await _persistTarget(
          prefs,
          _serverInfo!,
          typedHost: _pendingHost ?? result.host,
        );
      }
      final token = _client!.sessionToken;
      if (token != null && token.isNotEmpty) {
        for (final alias in <String>{
          _serverInfo!.stableKey,
          ..._serverInfo!.endpointAliases,
        }) {
          await _tokenStore.write(
            '$_sessionTokenKeyPrefix$alias',
            token,
            legacyPrefs: prefs,
          );
        }
      }
      // Force dependants through a visible connecting -> connected transition
      // so they can attach to the fresh HTTP client.
      _setStage(ConnectionStage.connecting);
      _finishConnection();
      oldClient?.dispose();
      return true;
    } catch (_) {
      if (_stage == ConnectionStage.needsAuth) {
        oldClient?.dispose();
        return false;
      }
      _client?.dispose();
      _client = oldClient;
      _serverInfo = currentInfo;
      return false;
    }
  }

  Future<void> autoConnect() async {
    if (_sameOriginUri != null) {
      await connectSameOrigin(_sameOriginUri);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final targetName = prefs.getString(_lastTargetKey);

    // The user chose offline mode last session: honour it without touching
    // the network. Endpoints are kept pending so goOnline can reconnect.
    if (targetName == _remoteTarget &&
        (prefs.getBool(_manualOfflineKey) ?? false)) {
      _currentTarget = _remoteTarget;
      _pendingHost = prefs.getString(_lastHostKey);
      _pendingPort = prefs.getInt(_lastPortKey) ?? 8080;
      _lastUsername = prefs.getString(_lastUsernameKey);
      _username = _lastUsername;
      _setStage(ConnectionStage.offline);
      return;
    }

    if (targetName == _localTarget) {
      final port = prefs.getInt(_lastPortKey);
      if (port != null) {
        await connectLocal(port: port);
        return;
      }
    }
    if (targetName == _remoteTarget) {
      final host = prefs.getString(_lastHostKey);
      final port = prefs.getInt(_lastPortKey);
      final scheme = prefs.getString(_lastSchemeKey) ?? 'http';
      if (host != null && port != null) {
        await connectRemote(
          host,
          port,
          scheme: scheme,
          knownLan: prefs.getString(_lastLanKey),
          knownTailscale: prefs.getString(_lastTailscaleKey),
          offlineFallbackOnFailure: true,
        );
        return;
      }
    }
    _setStage(ConnectionStage.idle);
  }

  Future<void> disconnect() async {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _launchRetryTimer?.cancel();
    _wakeWatchTimer?.cancel();
    _wakeWatchTimer = null;
    _isDisconnecting = true;
    try {
      await _client?.logout();
      final prefs = await SharedPreferences.getInstance();
      // An explicit sign-out also leaves offline mode.
      await prefs.remove(_manualOfflineKey);
      if (_serverInfo != null) {
        for (final alias in <String>{
          _serverInfo!.stableKey,
          ..._serverInfo!.endpointAliases,
        }) {
          await _tokenStore.delete(
            '$_sessionTokenKeyPrefix$alias',
            legacyPrefs: prefs,
          );
        }
      }
      await prefs.remove(_lastTargetKey);
    } finally {
      _isDisconnecting = false;
    }
    if (isSameOriginWeb) {
      final originInfo = _serverInfo;
      final baseUrl = originInfo?.baseUrl ??
          PlayerServerInfo(
            scheme: _pendingScheme,
            host: _pendingHost ?? _sameOriginUri!.host,
            port: _pendingPort,
            name: '',
            version: '',
          ).baseUrl;
      final deviceId = await _ensureDeviceId();
      _client?.dispose();
      _client = PlayerApiClient(
        baseUrl: baseUrl,
        deviceId: deviceId,
        deviceName: _deviceName,
        timeout: const Duration(seconds: 12),
      );
      _wireClientCallbacks(_client!);
      _username = null;
      _clearAvatar();
      _pairingCode = null;
      _setStage(ConnectionStage.needsAuth);
      return;
    }
    _client?.dispose();
    _client = null;
    _username = null;
    _clearAvatar();
    _pairingCode = null;
    _setStage(ConnectionStage.idle);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _launchRetryTimer?.cancel();
    _wakeWatchTimer?.cancel();
    _client?.dispose();
    super.dispose();
  }
}

class _EndpointProbe {
  const _EndpointProbe({
    required this.host,
    required this.info,
    required this.client,
  });

  final String host;
  final PlayerServerInfo info;
  final PlayerApiClient client;
}
