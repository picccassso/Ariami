import 'dart:async';
import 'dart:convert';
import 'package:ariami_core/models/auth_models.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/web_api_client.dart';
import '../services/web_auth_service.dart';
import '../utils/constants.dart';
import '../utils/web_clipboard.dart';
import '../utils/web_navigation.dart';
import '../widgets/endpoint_display.dart';

class QRCodeScreen extends StatefulWidget {
  const QRCodeScreen({super.key});

  @override
  State<QRCodeScreen> createState() => _QRCodeScreenState();
}

class QRCodeScreenArgs {
  const QRCodeScreenArgs({
    this.autoNavigateOnConnection = false,
  });

  final bool autoNavigateOnConnection;
}

class _QRCodeScreenState extends State<QRCodeScreen>
    with SingleTickerProviderStateMixin {
  final WebAuthService _authService = WebAuthService();
  late final WebApiClient _apiClient = WebApiClient(
    tokenProvider: _authService.getSessionToken,
  );
  String? _primaryServer;
  String? _lanServer;
  String? _tailscaleServer;
  int _serverPort = 8080;
  String _serverName = 'Loading...';
  bool _authRequired = false;
  String? _qrData;
  bool _isLoading = true;
  bool _isRefreshingAddresses = false;
  String? _errorMessage;
  DateTime? _lastEndpointRefresh;

  Timer? _connectionPollTimer;
  Timer? _serverInfoPollTimer;
  bool _isWaitingForConnection = false;
  late AnimationController _pulseController;

  // Manual-entry invite code (for phones that can't scan the QR).
  String? _inviteCode;
  DateTime? _inviteExpiresAt;
  bool _isGeneratingInvite = false;
  String? _inviteError;
  Timer? _inviteCountdownTimer;
  bool _didReadRouteArgs = false;
  bool _autoNavigateOnConnection = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _loadServerInfo();
  }

  @override
  void dispose() {
    _connectionPollTimer?.cancel();
    _serverInfoPollTimer?.cancel();
    _inviteCountdownTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didReadRouteArgs) return;

    final args = ModalRoute.of(context)?.settings.arguments;
    _autoNavigateOnConnection =
        args is QRCodeScreenArgs && args.autoNavigateOnConnection;
    _didReadRouteArgs = true;
  }

  Future<void> _generateInviteCode() async {
    setState(() {
      _isGeneratingInvite = true;
      _inviteError = null;
    });

    try {
      final response = await _apiClient.get('/api/admin/invite-code');

      if (response.isAuthError) {
        await _redirectToLoginIfSessionCannotRecover(response.errorCode);
        if (mounted) setState(() => _isGeneratingInvite = false);
        return;
      }

      if (response.statusCode == 200 && response.jsonBody != null) {
        final code = response.jsonBody!['inviteCode'] as String?;
        final expiresAtRaw = response.jsonBody!['expiresAt'] as String?;
        if (mounted) {
          setState(() {
            _inviteCode = code;
            _inviteExpiresAt = expiresAtRaw != null
                ? DateTime.tryParse(expiresAtRaw)?.toLocal()
                : null;
            _isGeneratingInvite = false;
          });
          _startInviteCountdown();
        }
      } else if (mounted) {
        setState(() {
          _inviteError = 'Failed to generate invite code';
          _isGeneratingInvite = false;
        });
      }
    } catch (e) {
      debugPrint('Error generating invite code: $e');
      if (mounted) {
        setState(() {
          _inviteError = 'Error: $e';
          _isGeneratingInvite = false;
        });
      }
    }
  }

  void _startInviteCountdown() {
    _inviteCountdownTimer?.cancel();
    _inviteCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final expiresAt = _inviteExpiresAt;
      if (expiresAt == null || !expiresAt.isAfter(DateTime.now())) {
        _inviteCountdownTimer?.cancel();
      }
      setState(() {});
    });
  }

  String _formatInviteCode(String code) =>
      code.length == 8 ? '${code.substring(0, 4)}-${code.substring(4)}' : code;

  String _inviteCountdownLabel() {
    final expiresAt = _inviteExpiresAt;
    if (expiresAt == null) return '';
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining.isNegative) return 'Expired — generate a new code';
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    return 'Expires in $minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _copyInviteCode() async {
    final code = _inviteCode;
    if (code == null) return;
    // Copy the raw 8-char code (no dash) so it pastes straight into the app.
    final copied = await copyToClipboard(code);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          copied
              ? 'Invite code copied'
              : 'Could not copy automatically — tap the code to select it, '
                  'then copy.',
        ),
        backgroundColor:
            copied ? AppTheme.surfaceBlack : Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _startServerInfoPolling() {
    _serverInfoPollTimer?.cancel();
    _serverInfoPollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_loadServerInfo(refreshOnly: true));
    });
  }

  /// Start polling for mobile app connections
  void _startConnectionPolling() {
    if (!_autoNavigateOnConnection) return;

    setState(() {
      _isWaitingForConnection = true;
    });

    _connectionPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkForConnections();
    });

    _checkForConnections();
  }

  Future<void> _checkForConnections() async {
    try {
      final response = await _apiClient.get('/api/stats');

      if (response.isAuthError) {
        // Do not wipe a valid saved session on a single transient
        // `AUTH_REQUIRED` (e.g. prefs/token race). Only force re-login when
        // there is no token or the server reports an expired session.
        final hasToken = await _authService.hasSessionToken();
        final code = response.errorCode;
        if (!hasToken || code == AuthErrorCodes.sessionExpired) {
          await _redirectToLogin();
        }
        return;
      }

      if (response.statusCode == 200) {
        final stats = response.jsonBody ?? <String, dynamic>{};
        final mobileClients = stats['mobileClients'] as int? ?? 0;

        if (mounted) {
          if (mobileClients > 0) {
            _connectionPollTimer?.cancel();
            navigateToDashboard(context);
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking connections: $e');
    }
  }

  Future<void> _loadServerInfo({bool refreshOnly = false}) async {
    try {
      final response = await _apiClient.get('/api/server-info');

      if (response.statusCode == 200) {
        final serverInfo = response.jsonBody ?? <String, dynamic>{};
        if (!await _addRegistrationToken(serverInfo)) {
          return;
        }

        if (mounted) {
          setState(() => _applyServerInfo(serverInfo));
          if (!refreshOnly) {
            _startConnectionPolling();
            _startServerInfoPolling();
          }
        }
      } else {
        if (mounted && !refreshOnly) {
          setState(() {
            _errorMessage = 'Failed to load server info';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading server info: $e');
      if (mounted && !refreshOnly) {
        setState(() {
          _errorMessage = 'Error: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshServerAddresses() async {
    if (_isRefreshingAddresses) return;

    setState(() {
      _isRefreshingAddresses = true;
      _errorMessage = null;
    });

    try {
      final response = await _apiClient.post('/api/server-info/refresh');
      if (response.statusCode == 200 && response.jsonBody != null) {
        if (!await _addRegistrationToken(response.jsonBody!)) {
          return;
        }
        if (mounted) {
          setState(() => _applyServerInfo(response.jsonBody!));
        }
      } else if (mounted) {
        setState(() {
          _errorMessage = 'Failed to refresh server addresses';
        });
      }
    } catch (e) {
      debugPrint('Error refreshing server addresses: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Error: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingAddresses = false;
          _isLoading = false;
        });
      }
    }
  }

  Future<bool> _addRegistrationToken(Map<String, dynamic> serverInfo) async {
    final response = await _apiClient.get('/api/admin/registration-token');
    if (response.isAuthError) {
      final didRedirect =
          await _redirectToLoginIfSessionCannotRecover(response.errorCode);
      if (didRedirect) return false;
      return false;
    }
    if (response.statusCode == 200 && response.jsonBody != null) {
      serverInfo.addAll(response.jsonBody!);
    }
    return true;
  }

  void _applyServerInfo(Map<String, dynamic> serverInfo) {
    _primaryServer = serverInfo['server'] as String? ?? 'Unknown';
    _lanServer = serverInfo['lanServer'] as String?;
    _tailscaleServer = serverInfo['tailscaleServer'] as String?;
    _serverPort = serverInfo['port'] as int? ?? 8080;
    _serverName = serverInfo['name'] as String? ?? 'Ariami Server';
    _authRequired = serverInfo['authRequired'] as bool? ?? false;
    _qrData = jsonEncode(serverInfo);
    _lastEndpointRefresh = DateTime.now();
    _isLoading = false;
  }

  Future<void> _redirectToLogin() async {
    _connectionPollTimer?.cancel();
    if (!mounted) return;
    await _authService.clearSessionToken();
    Navigator.pushReplacementNamed(context, '/login');
  }

  Future<bool> _redirectToLoginIfSessionCannotRecover(String? errorCode) async {
    final hasToken = await _authService.hasSessionToken();
    if (!hasToken || errorCode == AuthErrorCodes.sessionExpired) {
      await _redirectToLogin();
      return true;
    }
    return false;
  }

  void _closeQrScreen() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      navigateToDashboard(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.backgroundGradient,
        ),
        child: Column(
          children: [
            AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              automaticallyImplyLeading: false,
              title: const Text('CONNECT'),
              actions: [
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _closeQrScreen,
                ),
                IconButton(
                  tooltip: 'Refresh addresses',
                  icon: _isRefreshingAddresses
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.refresh_rounded),
                  onPressed: () {
                    _refreshServerAddresses();
                  },
                ),
                const SizedBox(width: 8),
              ],
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 820;
                  final isShort = constraints.maxHeight < 760;

                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      isNarrow ? 20 : 48,
                      isShort ? 12 : 24,
                      isNarrow ? 20 : 48,
                      32,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - (isShort ? 12 : 24),
                      ),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: isNarrow ? 560 : 1120,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.qr_code_2_rounded,
                                size: isShort ? 34 : 42,
                                color: Colors.white,
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'CONNECT MOBILE APP',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      fontSize: isNarrow ? 24 : 28,
                                      letterSpacing: 0,
                                    ),
                              ),
                              SizedBox(height: isShort ? 24 : 40),
                              if (_errorMessage != null)
                                _buildErrorState()
                              else if (_isLoading || _qrData == null)
                                const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                )
                              else
                                _buildConnectionContent(isNarrow: isNarrow),
                              SizedBox(height: isShort ? 24 : 32),
                              _buildDashboardButton(isNarrow: isNarrow),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionContent({required bool isNarrow}) {
    if (isNarrow) {
      return Column(
        children: [
          _buildQrPanel(qrSize: 200),
          const SizedBox(height: 24),
          _buildServerInfoCard(isNarrow: true),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 3,
          child: _buildServerInfoCard(isNarrow: false),
        ),
        const SizedBox(width: 48),
        Expanded(
          flex: 2,
          child: _buildQrPanel(qrSize: 220),
        ),
      ],
    );
  }

  Widget _buildServerInfoCard({required bool isNarrow}) {
    return Container(
      width: double.infinity,
      decoration: AppTheme.glassDecoration,
      padding: EdgeInsets.all(isNarrow ? 20.0 : 32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SERVER INFORMATION',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppTheme.textSecondary,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          _buildInfoRow('NAME', _serverName),
          const SizedBox(height: 16),
          ..._buildEndpointSection(),
          if (_lastEndpointRefresh != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  size: 14,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Updated ${_formatEndpointRefreshTime()}',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          _buildInfoRow('PORT', '$_serverPort'),
          const SizedBox(height: 16),
          _buildInfoRow('AUTH', _authRequired ? 'REQUIRED' : 'OPEN'),
          const SizedBox(height: 24),
          const Divider(color: Colors.white10),
          const SizedBox(height: 24),
          const Text(
            'INSTRUCTIONS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppTheme.textSecondary,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '1. Open Ariami Mobile App\n2. Scan the QR code\n3. Wait for connection',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white70,
              height: 1.6,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 24),
          const Divider(color: Colors.white10),
          const SizedBox(height: 24),
          ..._buildManualEntrySection(),
        ],
      ),
    );
  }

  Widget _buildQrPanel({required double qrSize}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.1),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: QrImageView(
            data: _qrData!,
            version: QrVersions.auto,
            size: qrSize,
            backgroundColor: Colors.white,
            padding: EdgeInsets.zero,
          ),
        ),
        if (_isWaitingForConnection) ...[
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FadeTransition(
                opacity: _pulseController,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'WAITING...',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textSecondary,
                  letterSpacing: 2.0,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildDashboardButton({required bool isNarrow}) {
    return SizedBox(
      height: 56,
      width: isNarrow ? double.infinity : 280,
      child: ElevatedButton(
        onPressed: () {
          navigateToDashboard(context);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.surfaceBlack,
          foregroundColor: Colors.white,
          side: const BorderSide(color: AppTheme.borderGrey),
        ),
        child: const Text('GO TO DASHBOARD'),
      ),
    );
  }

  List<Widget> _buildEndpointSection() {
    final lan = _lanServer;
    final ts = _tailscaleServer;
    final primary = _primaryServer;

    if (lan != null || ts != null) {
      return [
        const Text(
          'AVAILABLE ENDPOINTS',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 12),
        if (lan != null) ...[
          EndpointDisplay(
            label: 'Local Network',
            value: lan,
            badgeLabel: 'LAN',
            dense: true,
          ),
          if (ts != null) const SizedBox(height: 16),
        ],
        if (ts != null)
          EndpointDisplay(
            label: 'Tailscale',
            value: ts,
            badgeLabel: 'REMOTE',
            dense: true,
          ),
      ];
    }

    if (primary != null && primary.isNotEmpty) {
      return [
        _buildInfoRow('ADDRESS', primary),
      ];
    }

    return [
      _buildInfoRow('ADDRESS', 'Unknown'),
    ];
  }

  List<Widget> _buildManualEntrySection() {
    final code = _inviteCode;
    return [
      const Text(
        "CAN'T SCAN? MANUAL ENTRY",
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: AppTheme.textSecondary,
          letterSpacing: 1.5,
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'In the app, tap "Manual entry", type the address above, then this '
        'one-time invite code:',
        style: TextStyle(
          fontSize: 14,
          color: Colors.white70,
          height: 1.6,
          fontWeight: FontWeight.w500,
        ),
      ),
      const SizedBox(height: 16),
      if (_inviteError != null) ...[
        Text(
          _inviteError!,
          style: const TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
      ],
      if (code == null)
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _isGeneratingInvite ? null : _generateInviteCode,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.surfaceBlack,
              foregroundColor: Colors.white,
              side: const BorderSide(color: AppTheme.borderGrey),
            ),
            icon: _isGeneratingInvite
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.vpn_key_rounded, size: 18),
            label: const Text('GENERATE INVITE CODE'),
          ),
        )
      else ...[
        // Tapping anywhere on the code copies it; the text is also selectable
        // so a manual long-press → copy works on any mobile browser.
        InkWell(
          onTap: _copyInviteCode,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceBlack,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderGrey),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    _formatInviteCode(code),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3.0,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.copy_rounded, color: Colors.white70),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _copyInviteCode,
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('COPY CODE'),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.schedule_rounded,
                size: 14, color: AppTheme.textSecondary),
            const SizedBox(width: 6),
            Text(
              _inviteCountdownLabel(),
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: _isGeneratingInvite ? null : _generateInviteCode,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Generate new code'),
        ),
      ],
    ];
  }

  Widget _buildErrorState() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 500),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.redAccent.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Colors.redAccent, size: 48),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            style: const TextStyle(
                color: Colors.redAccent, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _isLoading = true;
                _errorMessage = null;
              });
              _loadServerInfo();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('RETRY'),
          ),
        ],
      ),
    );
  }

  String _formatEndpointRefreshTime() {
    final value = _lastEndpointRefresh;
    if (value == null) return 'Never';

    final now = DateTime.now();
    final difference = now.difference(value);
    if (difference.inSeconds < 5) return 'just now';
    if (difference.inMinutes < 1) return '${difference.inSeconds}s ago';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';

    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return 'at $hour:$minute';
  }

  Widget _buildInfoRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}
