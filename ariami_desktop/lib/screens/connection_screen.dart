import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'package:ariami_core/ariami_core.dart';
import '../onboarding/onboarding_copy.dart';
import '../onboarding/setup_scaffold.dart';
import '../services/desktop_tailscale_service.dart';
import '../services/desktop_state_service.dart';
import '../services/server_initialization_service.dart';
import 'scanning_screen.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final DesktopTailscaleService _tailscaleService = DesktopTailscaleService();
  final AriamiHttpServer _httpServer = AriamiHttpServer();
  final DesktopStateService _stateService = DesktopStateService();
  final ServerInitializationService _serverInit = ServerInitializationService();

  String? _tailscaleIP;
  String? _lanIP;
  bool _isLoading = true;
  String _errorMessage = '';
  bool _serverStarted = false;
  bool _hasOwnerAccount = false;
  bool _ownerSetupSkipped = false;
  StreamSubscription<Map<String, dynamic>>? _endpointsSubscription;

  // Manual-entry invite code (for phones that can't scan the QR).
  String? _inviteCode;
  DateTime? _inviteExpiresAt;
  Timer? _inviteCountdownTimer;

  @override
  void initState() {
    super.initState();
    _endpointsSubscription =
        _httpServer.onEndpointsChanged.listen(_onEndpointsChanged);
    _initializeServer();
    // Listen for client connections to auto-navigate to dashboard
    _httpServer.connectionManager.addListener(_onClientConnected);
  }

  @override
  void dispose() {
    _endpointsSubscription?.cancel();
    _inviteCountdownTimer?.cancel();
    _httpServer.connectionManager.removeListener(_onClientConnected);
    super.dispose();
  }

  void _generateInviteCode() {
    // The desktop holds the server in-process, so mint the code directly.
    final payload = _httpServer.createInviteCode();
    final code = payload['inviteCode'] as String?;
    final expiresAtRaw = payload['expiresAt'] as String?;
    setState(() {
      _inviteCode = code;
      _inviteExpiresAt = expiresAtRaw != null
          ? DateTime.tryParse(expiresAtRaw)?.toLocal()
          : null;
    });
    _startInviteCountdown();
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
    await Clipboard.setData(ClipboardData(text: _formatInviteCode(code)));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invite code copied')),
      );
    }
  }

  void _onEndpointsChanged(Map<String, dynamic> serverInfo) {
    if (!mounted) return;
    setState(() {
      _tailscaleIP = serverInfo['tailscaleServer'] as String?;
      _lanIP = serverInfo['lanServer'] as String?;
    });
  }

  void _onClientConnected() async {
    if (_httpServer.connectionManager.clientCount > 0 && mounted) {
      // Mark setup as complete and navigate to dashboard
      await _stateService.markSetupComplete();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/dashboard');
      }
    }
  }

  Future<void> _initializeServer() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      await _serverInit.configureLibraryCacheAndFeatureFlags(_httpServer);
      ServerInitializationService.configureNetworkDiscovery(
        _httpServer,
        _tailscaleService,
      );

      // Check if server is already running
      if (_httpServer.isRunning) {
        await _refreshOwnerSetupState();
        if (!_hasOwnerAccount) {
          await _httpServer.stop();
          if (mounted) {
            Navigator.pushReplacementNamed(context, '/owner-setup');
          }
          return;
        }

        final serverInfo = _httpServer.getServerInfo();
        final existingIp = serverInfo['server'] as String?;

        // Validate that we have a valid IP
        if (existingIp == null || existingIp.isEmpty) {
          setState(() {
            _errorMessage =
                'Server is running but has no valid IP.\nPlease restart the application.';
            _isLoading = false;
          });
          return;
        }

        setState(() {
          _tailscaleIP = serverInfo['tailscaleServer'] as String?;
          _lanIP = serverInfo['lanServer'] as String?;
          _serverStarted = true;
          _isLoading = false;
        });
        return;
      }

      final tailscaleIp = await _tailscaleService.getTailscaleIp();
      final lanIp = await _tailscaleService.getLanIp();

      if (tailscaleIp == null && lanIp == null) {
        setState(() {
          _errorMessage =
              'No usable network address was found.\nPlease connect to your local network and try again.';
          _isLoading = false;
        });
        return;
      }

      final advertisedIp = tailscaleIp ?? lanIp!;

      await ServerInitializationService.initializeAuth(
          _httpServer, _stateService);
      await _refreshOwnerSetupState();
      if (!_hasOwnerAccount) {
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/owner-setup');
        }
        return;
      }
      await ServerInitializationService.applyDesktopDownloadLimits(_httpServer);

      // Start HTTP server (singleton will prevent double-start)
      final startResult =
          await ServerInitializationService.startListeningServer(
        httpServer: _httpServer,
        stateService: _stateService,
        advertisedIp: advertisedIp,
        tailscaleIp: tailscaleIp,
        lanIp: lanIp,
      );
      if (startResult.fallbackMessage != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(startResult.fallbackMessage!),
            duration: const Duration(seconds: 5),
          ),
        );
      }

      // Check if we need to scan before showing the QR code
      final prefs = await SharedPreferences.getInstance();
      final musicFolderPath = prefs.getString('music_folder_path');

      if (musicFolderPath != null &&
          musicFolderPath.isNotEmpty &&
          _httpServer.libraryManager.library == null &&
          mounted) {
        print(
            '[ConnectionScreen] Navigating to scanning screen: $musicFolderPath');
        // Replace with scanning screen, which will then navigate forward to /connection
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ScanningScreen(
              musicFolderPath: musicFolderPath,
              nextRoute: '/connection',
            ),
          ),
        );
        return; // Don't update state, we're navigating away
      }

      // No scan needed, just show QR code
      if (mounted) {
        setState(() {
          _tailscaleIP = tailscaleIp;
          _lanIP = lanIp;
          _serverStarted = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e is PortBindingException
            ? e.toString()
            : 'Error starting server: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshOwnerSetupState() async {
    final hasOwner = await _stateService.hasOwnerAccount();
    final skipped = await _stateService.isOwnerSetupSkipped();
    if (!mounted) return;
    setState(() {
      _hasOwnerAccount = hasOwner;
      _ownerSetupSkipped = skipped;
    });
  }

  String _generateQRData() {
    if (!_serverStarted) return '';

    // Generate server info for QR code (matching Phase 4 spec)
    final serverInfo = _httpServer.getServerInfo(
      includeRegistrationToken: true,
    );

    // Validate that server info has a valid IP before generating QR code
    final serverIp = serverInfo['server'];
    if (serverIp == null || serverIp.toString().isEmpty) {
      return '';
    }

    return jsonEncode(serverInfo);
  }

  Widget _buildManualEntrySection() {
    final code = _inviteCode;
    return Container(
      constraints: const BoxConstraints(maxWidth: 460),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        children: [
          Text(
            "Can't scan? Manual entry".toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white54,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'In the app, tap "Manual entry", type one of the addresses above, '
            'then this one-time invite code:',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 16),
          if (code == null)
            ElevatedButton.icon(
              onPressed: _generateInviteCode,
              icon: const Icon(Icons.vpn_key_rounded, size: 18),
              label: const Text('Generate Invite Code'),
            )
          else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SelectableText(
                  _formatInviteCode(code),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 4.0,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Copy code',
                  icon: const Icon(Icons.copy_rounded, color: Colors.white),
                  onPressed: _copyInviteCode,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _inviteCountdownLabel(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white54,
              ),
            ),
            TextButton.icon(
              onPressed: _generateInviteCode,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Generate new code'),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SetupScreenScaffold(
      title: 'Connect Mobile App',
      helpTopic: OnboardingCopy.connectDevices,
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(
                  Icons.qr_code_2_rounded,
                  size: 64,
                  color: Colors.white,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Connect Your Mobile App',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 16),
                if (!_hasOwnerAccount && _ownerSetupSkipped)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: Colors.orange.shade300),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Owner setup is still pending. Owner-only actions in Dashboard remain locked until you create the first account.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white,
                              height: 1.4,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () async {
                            await Navigator.pushNamed(context, '/owner-setup');
                            await _refreshOwnerSetupState();
                          },
                          child: const Text('Set Up Owner'),
                        ),
                      ],
                    ),
                  ),
                if (_isLoading)
                  Column(
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 16),
                      const Text(
                        'Starting server...',
                        style: TextStyle(fontSize: 16, color: Colors.white70),
                      ),
                    ],
                  )
                else if (_errorMessage.isNotEmpty)
                  Column(
                    children: [
                      Text(
                        _errorMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _initializeServer,
                        child: const Text('Retry'),
                      ),
                    ],
                  )
                else if (_tailscaleIP != null || _lanIP != null) ...[
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Left Side: IP Address
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 32),
                              decoration: BoxDecoration(
                                color: const Color(0xFF141414),
                                borderRadius: BorderRadius.circular(24),
                                border:
                                    Border.all(color: const Color(0xFF2A2A2A)),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    'Available Endpoints'.toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white54,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  if (_lanIP != null) ...[
                                    _EndpointDisplay(
                                      label: 'Local Network',
                                      value: _lanIP!,
                                      badgeLabel: 'LAN',
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  if (_tailscaleIP != null)
                                    _EndpointDisplay(
                                      label: 'Tailscale',
                                      value: _tailscaleIP!,
                                      badgeLabel: 'REMOTE',
                                    ),
                                  if (_tailscaleIP == null)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 4),
                                      child: Text(
                                        'Local setup is available now. Install Tailscale later for remote access.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.white70,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 16),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: _httpServer.authRequired
                                          ? Colors.orange.withValues(alpha: 0.2)
                                          : Colors.green.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: _httpServer.authRequired
                                            ? Colors.orange
                                                .withValues(alpha: 0.5)
                                            : Colors.green
                                                .withValues(alpha: 0.5),
                                      ),
                                    ),
                                    child: Text(
                                      _httpServer.authRequired
                                          ? 'AUTH REQUIRED'
                                          : 'OPEN ACCESS',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: _httpServer.authRequired
                                            ? Colors.orange
                                            : Colors.green,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 32),
                      // Right Side: QR Code + Instructions
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: QrImageView(
                                data: _generateQRData(),
                                version: QrVersions.auto,
                                size: 200.0,
                                eyeStyle: const QrEyeStyle(
                                  eyeShape: QrEyeShape.square,
                                  color: Colors.black,
                                ),
                                dataModuleStyle: const QrDataModuleStyle(
                                  dataModuleShape: QrDataModuleShape.square,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'Instructions',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '1. Open Ariami Mobile App\n'
                              '2. Scan this QR code\n'
                              '3. Wait for connection to establish',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white70,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildManualEntrySection(),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () async {
                      await _stateService.markSetupComplete();
                      if (!context.mounted) return;
                      Navigator.pushReplacementNamed(context, '/dashboard');
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF333333)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 48,
                        vertical: 20,
                      ),
                      shape: const StadiumBorder(),
                    ),
                    child: const Text(
                      'Continue to Dashboard',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EndpointDisplay extends StatelessWidget {
  const _EndpointDisplay({
    required this.label,
    required this.value,
    required this.badgeLabel,
  });

  final String label;
  final String value;
  final String badgeLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white54,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFF333333)),
              ),
              child: Text(
                badgeLabel,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SelectableText(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}
