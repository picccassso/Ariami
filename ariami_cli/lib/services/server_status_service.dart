import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/ariami_core.dart';
import 'package:path/path.dart' as p;

import 'cli_state_service.dart';
import 'cli_status_info.dart';
import 'cli_tailscale_service.dart';
import 'daemon_service.dart';

typedef ServerInfoFetcher = Future<Map<String, dynamic>?> Function(
  Uri uri,
  Duration timeout,
);
typedef BoolLookup = Future<bool> Function();
typedef NullableIntLookup = Future<int?> Function();
typedef ServerStateLookup = Future<Map<String, dynamic>?> Function();
typedef NullableStringLookup = Future<String?> Function();
typedef AuthSummaryLookup = Future<AuthSummary> Function();
typedef PathExistsLookup = Future<bool> Function(String path);
typedef StringLookup = String Function();
typedef DateTimeLookup = DateTime Function();

/// Snapshot of the CLI server, local config, and safe auth summary.
class StatusSnapshot {
  const StatusSnapshot({
    required this.cliVersion,
    required this.isRunning,
    required this.port,
    required this.isReachable,
    required this.setupComplete,
    required this.dataDir,
    required this.configFilePath,
    required this.catalogDbFilePath,
    required this.metadataCacheFilePath,
    required this.artworkCacheDirPath,
    required this.transcodedCacheDirPath,
    this.pid,
    this.uptime,
    this.serverVersion,
    this.lanIp,
    this.tailscaleIp,
    this.musicFolderPath,
    this.musicFolderExists,
    this.accountCount,
    this.hasOwnerAccount,
    this.authReadable = true,
  });

  final String cliVersion;
  final bool isRunning;
  final int? pid;
  final Duration? uptime;
  final int port;
  final bool isReachable;
  final String? serverVersion;
  final String? lanIp;
  final String? tailscaleIp;
  final bool setupComplete;
  final String? musicFolderPath;
  final bool? musicFolderExists;
  final int? accountCount;
  final bool? hasOwnerAccount;
  final bool authReadable;
  final String dataDir;
  final String configFilePath;
  final String catalogDbFilePath;
  final String metadataCacheFilePath;
  final String artworkCacheDirPath;
  final String transcodedCacheDirPath;
}

/// Collects and formats a health-check view for self-hosted Ariami installs.
class ServerStatusService {
  ServerStatusService._({
    required ServerInfoFetcher fetchServerInfo,
    required BoolLookup isRunning,
    required NullableIntLookup getServerPid,
    required ServerStateLookup getServerState,
    required NullableIntLookup getServerPort,
    required NullableStringLookup getLanIp,
    required NullableStringLookup getTailscaleIp,
    required BoolLookup isSetupComplete,
    required NullableStringLookup getMusicFolderPath,
    required AuthSummaryLookup readAuth,
    required PathExistsLookup pathExists,
    required StringLookup getConfigDir,
    required StringLookup getConfigFilePath,
    required StringLookup getCatalogDbFilePath,
    required StringLookup getMetadataCacheFilePath,
    required StringLookup getArtworkCacheDirPath,
    required StringLookup getTranscodedCacheDirPath,
    required DateTimeLookup now,
  })  : _fetchServerInfo = fetchServerInfo,
        _isRunning = isRunning,
        _getServerPid = getServerPid,
        _getServerState = getServerState,
        _getServerPort = getServerPort,
        _getLanIp = getLanIp,
        _getTailscaleIp = getTailscaleIp,
        _isSetupComplete = isSetupComplete,
        _getMusicFolderPath = getMusicFolderPath,
        _readAuth = readAuth,
        _pathExists = pathExists,
        _getConfigDir = getConfigDir,
        _getConfigFilePath = getConfigFilePath,
        _getCatalogDbFilePath = getCatalogDbFilePath,
        _getMetadataCacheFilePath = getMetadataCacheFilePath,
        _getArtworkCacheDirPath = getArtworkCacheDirPath,
        _getTranscodedCacheDirPath = getTranscodedCacheDirPath,
        _now = now;

  factory ServerStatusService({
    ServerInfoFetcher? fetchServerInfo,
    BoolLookup? isRunning,
    NullableIntLookup? getServerPid,
    ServerStateLookup? getServerState,
    NullableIntLookup? getServerPort,
    NullableStringLookup? getLanIp,
    NullableStringLookup? getTailscaleIp,
    BoolLookup? isSetupComplete,
    NullableStringLookup? getMusicFolderPath,
    AuthSummaryLookup? readAuth,
    PathExistsLookup? pathExists,
    StringLookup? getConfigDir,
    StringLookup? getConfigFilePath,
    StringLookup? getCatalogDbFilePath,
    StringLookup? getMetadataCacheFilePath,
    StringLookup? getArtworkCacheDirPath,
    StringLookup? getTranscodedCacheDirPath,
    DateTimeLookup? now,
  }) {
    final daemonService = DaemonService();
    final stateService = CliStateService();
    final tailscaleService = CliTailscaleService();

    return ServerStatusService._(
      fetchServerInfo: fetchServerInfo ?? _fetchServerInfoWithHttpClient,
      isRunning: isRunning ?? daemonService.isRunning,
      getServerPid: getServerPid ?? daemonService.getServerPid,
      getServerState: getServerState ?? daemonService.getServerState,
      getServerPort: getServerPort ?? stateService.getServerPort,
      getLanIp: getLanIp ?? tailscaleService.getLanIp,
      getTailscaleIp: getTailscaleIp ?? tailscaleService.getTailscaleIp,
      isSetupComplete: isSetupComplete ?? stateService.isSetupComplete,
      getMusicFolderPath: getMusicFolderPath ?? stateService.getMusicFolderPath,
      readAuth: readAuth ?? readAuthSummary,
      pathExists: pathExists ?? _defaultPathExists,
      getConfigDir: getConfigDir ?? CliStateService.getConfigDir,
      getConfigFilePath:
          getConfigFilePath ?? CliStateService.getConfigFilePath,
      getCatalogDbFilePath:
          getCatalogDbFilePath ?? CliStateService.getCatalogDbFilePath,
      getMetadataCacheFilePath:
          getMetadataCacheFilePath ?? CliStateService.getMetadataCacheFilePath,
      getArtworkCacheDirPath:
          getArtworkCacheDirPath ?? CliStateService.getArtworkCacheDirPath,
      getTranscodedCacheDirPath:
          getTranscodedCacheDirPath ??
              CliStateService.getTranscodedCacheDirPath,
      now: now ?? DateTime.now,
    );
  }

  static const String cliVersion = kAriamiVersion;
  static const Duration serverInfoTimeout = Duration(seconds: 2);

  final ServerInfoFetcher _fetchServerInfo;
  final BoolLookup _isRunning;
  final NullableIntLookup _getServerPid;
  final ServerStateLookup _getServerState;
  final NullableIntLookup _getServerPort;
  final NullableStringLookup _getLanIp;
  final NullableStringLookup _getTailscaleIp;
  final BoolLookup _isSetupComplete;
  final NullableStringLookup _getMusicFolderPath;
  final AuthSummaryLookup _readAuth;
  final PathExistsLookup _pathExists;
  final StringLookup _getConfigDir;
  final StringLookup _getConfigFilePath;
  final StringLookup _getCatalogDbFilePath;
  final StringLookup _getMetadataCacheFilePath;
  final StringLookup _getArtworkCacheDirPath;
  final StringLookup _getTranscodedCacheDirPath;
  final DateTimeLookup _now;

  /// Collect a status snapshot from local state and the running server.
  Future<StatusSnapshot> collectSnapshot() async {
    final running = await _isRunning();
    final serverState = await _getServerState();
    final configuredPort = await _getServerPort();
    final statePort = _readInt(serverState?['port']);
    var port = statePort ?? configuredPort ?? 8080;
    final pid = running ? await _getServerPid() : null;
    final uptime = running ? _readUptime(serverState?['started_at']) : null;

    Map<String, dynamic>? serverInfo;
    if (running) {
      final uri = Uri.parse('http://127.0.0.1:$port/api/server-info');
      serverInfo = await _fetchServerInfo(uri, serverInfoTimeout);
      port = _readInt(serverInfo?['port']) ?? port;
    }

    final musicFolderPath = await _getMusicFolderPath();
    final musicFolderExists = musicFolderPath == null
        ? null
        : await _pathExists(musicFolderPath);
    final authSummary = serverInfo == null ? await _readAuth() : null;
    final liveAccountCount = _readInt(serverInfo?['registeredUsers']);
    final liveHasUsers = serverInfo?['hasUsers'] is bool
        ? serverInfo!['hasUsers'] as bool
        : null;
    final accountCount = liveAccountCount ?? authSummary?.accountCount;

    return StatusSnapshot(
      cliVersion: cliVersion,
      isRunning: running,
      pid: pid,
      uptime: uptime,
      port: port,
      isReachable: serverInfo != null,
      serverVersion: serverInfo?['version'] is String
          ? serverInfo!['version'] as String
          : null,
      lanIp: await _getLanIp(),
      tailscaleIp: await _getTailscaleIp(),
      setupComplete: await _isSetupComplete(),
      musicFolderPath: musicFolderPath,
      musicFolderExists: musicFolderExists,
      accountCount: accountCount,
      hasOwnerAccount:
          liveHasUsers ??
              authSummary?.hasOwnerAccount ??
              _hasAccount(accountCount),
      authReadable: authSummary?.readable ?? true,
      dataDir: _getConfigDir(),
      configFilePath: _getConfigFilePath(),
      catalogDbFilePath: _getCatalogDbFilePath(),
      metadataCacheFilePath: _getMetadataCacheFilePath(),
      artworkCacheDirPath: _getArtworkCacheDirPath(),
      transcodedCacheDirPath: _getTranscodedCacheDirPath(),
    );
  }

  /// Format a status snapshot without reading disk or touching the network.
  static List<String> formatStatus(StatusSnapshot snapshot) {
    final lines = <String>[
      'Ariami CLI ${snapshot.cliVersion}',
      _line('Server', _formatServer(snapshot)),
    ];

    if (snapshot.isRunning) {
      lines.add(_line('Reachable', _formatReachable(snapshot)));
      if (snapshot.serverVersion != null &&
          snapshot.serverVersion != snapshot.cliVersion) {
        lines.add(_line(
          'Version',
          'server reports ${snapshot.serverVersion} '
              '(CLI is ${snapshot.cliVersion})',
        ));
      }
      if (snapshot.lanIp != null) {
        lines.add(_line('Dashboard', _url(snapshot.lanIp!, snapshot.port)));
      }
      lines.add(_line('Local', _localUrl(snapshot)));
      if (snapshot.tailscaleIp != null) {
        lines.add(
          _line('Tailscale', _url(snapshot.tailscaleIp!, snapshot.port)),
        );
      }
    } else {
      lines.add(_line('Start it with', 'ariami_cli start'));
    }

    lines
      ..add(_line('Setup', _formatSetup(snapshot)))
      ..add(_line('Music', _formatMusic(snapshot)))
      ..add(_line('Auth', _formatAuth(snapshot)))
      ..add(_line('Data', snapshot.dataDir))
      ..add('  ${_line('Config', _fileName(snapshot.configFilePath))}')
      ..add(
        '  ${_line(
          'Database',
          '${_fileName(snapshot.catalogDbFilePath)}, '
              '${_fileName(snapshot.metadataCacheFilePath)}',
        )}',
      )
      ..add(
        '  ${_line(
          'Caches',
          '${_dirName(snapshot.artworkCacheDirPath)}, '
              '${_dirName(snapshot.transcodedCacheDirPath)}',
        )}',
      )
      ..add(
        _line(
          'Backup',
          'back up the data directory above. Your music files live separately '
              'in the music folder.',
        ),
      );

    return lines;
  }

  static String _formatServer(StatusSnapshot snapshot) {
    if (!snapshot.isRunning) {
      return 'stopped';
    }

    final details = <String>[];
    if (snapshot.pid != null) {
      details.add('PID ${snapshot.pid}');
    }
    if (snapshot.uptime != null) {
      details.add('up ${_formatDuration(snapshot.uptime!)}');
    }
    if (details.isEmpty) {
      return 'running';
    }
    return 'running (${details.join(', ')})';
  }

  static String _formatReachable(StatusSnapshot snapshot) {
    if (snapshot.isReachable) {
      return 'yes — dashboard responding on port ${snapshot.port}';
    }
    return 'NO — process is running but the dashboard did not respond on port '
        '${snapshot.port}. Try "ariami_cli stop" then "ariami_cli start".';
  }

  static String _formatSetup(StatusSnapshot snapshot) {
    if (snapshot.setupComplete) {
      return 'complete';
    }
    return 'not complete — run "ariami_cli start" and open the dashboard to '
        'finish setup';
  }

  static String _formatMusic(StatusSnapshot snapshot) {
    final path = snapshot.musicFolderPath;
    if (path == null || path.isEmpty) {
      return 'not configured';
    }
    if (snapshot.musicFolderExists == false) {
      return '$path (folder missing!)';
    }
    return path;
  }

  static String _formatAuth(StatusSnapshot snapshot) {
    if (!snapshot.authReadable) {
      return 'enabled — account store unreadable';
    }
    if (snapshot.hasOwnerAccount != true) {
      return 'enabled — no owner account yet. Create one in the dashboard.';
    }

    final count = snapshot.accountCount ?? 0;
    final noun = count == 1 ? 'account' : 'accounts';
    return 'enabled — $count $noun';
  }

  static String _localUrl(StatusSnapshot snapshot) {
    return _url('127.0.0.1', snapshot.port);
  }

  static String _url(String host, int port) {
    return 'http://$host:$port';
  }

  static String _line(String label, String value) {
    final prefix = '$label:';
    return '${prefix.length >= 11 ? '$prefix ' : prefix.padRight(11)}$value';
  }

  static String _fileName(String path) {
    return p.basename(path);
  }

  static String _dirName(String path) {
    return '${p.basename(path)}/';
  }

  static String _formatDuration(Duration duration) {
    if (duration.inDays > 0) {
      final hours = duration.inHours.remainder(24);
      return hours > 0
          ? '${duration.inDays}d ${hours}h'
          : '${duration.inDays}d';
    }

    if (duration.inHours > 0) {
      final minutes = duration.inMinutes.remainder(60);
      return minutes > 0
          ? '${duration.inHours}h ${minutes}m'
          : '${duration.inHours}h';
    }

    if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m';
    }

    return '<1m';
  }

  Duration? _readUptime(Object? startedAt) {
    if (startedAt is! String) {
      return null;
    }

    final parsed = DateTime.tryParse(startedAt);
    if (parsed == null) {
      return null;
    }

    final uptime = _now().difference(parsed);
    if (uptime.isNegative) {
      return null;
    }
    return uptime;
  }

  static int? _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  static bool? _hasAccount(int? accountCount) {
    if (accountCount == null) {
      return null;
    }
    return accountCount > 0;
  }

  static Future<bool> _defaultPathExists(String path) {
    return Directory(path).exists();
  }

  static Future<Map<String, dynamic>?> _fetchServerInfoWithHttpClient(
    Uri uri,
    Duration timeout,
  ) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        return null;
      }

      final body = await response.transform(utf8.decoder).join().timeout(
            timeout,
          );
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
