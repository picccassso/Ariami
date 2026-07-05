import 'package:flutter/material.dart';
import '../services/web_tailscale_service.dart';
import '../utils/constants.dart';
import '../widgets/endpoint_display.dart';

class TailscaleCheckScreen extends StatefulWidget {
  const TailscaleCheckScreen({super.key});

  @override
  State<TailscaleCheckScreen> createState() => _TailscaleCheckScreenState();
}

class _TailscaleCheckScreenState extends State<TailscaleCheckScreen>
    with SingleTickerProviderStateMixin {
  final WebTailscaleService _tailscaleService = WebTailscaleService();

  bool _isChecking = true;
  bool _isInstalled = false;
  bool _isRunning = false;
  bool _isContainerized = false;
  String? _tailscaleIp;
  String? _lanServer;
  String? _tailscaleServer;
  String? _advertisedLanHost;
  String? _advertisedTailscaleHost;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _checkTailscale();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _checkTailscale() async {
    setState(() => _isChecking = true);

    try {
      final status = await _tailscaleService.checkTailscaleStatus();
      final endpoints = await _tailscaleService.fetchServerEndpoints();

      if (mounted) {
        setState(() {
          _isChecking = false;
          _isInstalled = status['isInstalled'] as bool? ?? false;
          _isRunning = status['isRunning'] as bool? ?? false;
          _isContainerized = status['containerized'] as bool? ?? false;
          _tailscaleIp = status['ip'] as String?;
          _advertisedLanHost = status['advertisedLanHost'] as String?;
          _advertisedTailscaleHost =
              status['advertisedTailscaleHost'] as String?;
          _lanServer = endpoints['lanServer'];
          _tailscaleServer = endpoints['tailscaleServer'];
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isChecking = false;
          _isInstalled = false;
          _isRunning = false;
          _isContainerized = false;
          _tailscaleIp = null;
          _advertisedLanHost = null;
          _advertisedTailscaleHost = null;
          _lanServer = null;
          _tailscaleServer = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lanEndpoint = _advertisedLanHost ?? _lanServer;
    final tailscaleEndpoint =
        _advertisedTailscaleHost ?? _tailscaleServer ?? _tailscaleIp;

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
              title: const Text('SETUP'),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Pulse Status Icon
                        FadeTransition(
                          opacity: _pulseController,
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: _isRunning
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : (_isInstalled
                                      ? Colors.amberAccent
                                          .withValues(alpha: 0.05)
                                      : Colors.redAccent
                                          .withValues(alpha: 0.05)),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _isRunning
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : (_isInstalled
                                        ? Colors.amberAccent
                                            .withValues(alpha: 0.1)
                                        : Colors.redAccent
                                            .withValues(alpha: 0.1)),
                              ),
                            ),
                            child: Icon(
                              _isRunning
                                  ? Icons.vpn_lock_rounded
                                  : (_isInstalled
                                      ? Icons.info_rounded
                                      : Icons.info_outline_rounded),
                              size: 64,
                              color: _isRunning
                                  ? Colors.white
                                  : (_isInstalled
                                      ? Colors.amberAccent
                                      : Colors.redAccent),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          'TAILSCALE SECURITY',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: Text(
                            _statusMessage(),
                            style: const TextStyle(
                              fontSize: 16,
                              color: AppTheme.textSecondary,
                              height: 1.5,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 56),

                        if (_isChecking)
                          const CircularProgressIndicator(color: Colors.white)
                        else if (lanEndpoint != null ||
                            tailscaleEndpoint != null)
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 440),
                            child: Column(
                              children: [
                                if (lanEndpoint != null)
                                  Container(
                                    width: double.infinity,
                                    decoration: AppTheme.glassDecoration,
                                    padding: const EdgeInsets.all(24.0),
                                    child: EndpointDisplay(
                                      label: 'Local Network',
                                      value: lanEndpoint,
                                      badgeLabel: 'LAN',
                                    ),
                                  ),
                                if (lanEndpoint != null &&
                                    tailscaleEndpoint != null)
                                  const SizedBox(height: 16),
                                if (tailscaleEndpoint != null)
                                  Container(
                                    width: double.infinity,
                                    decoration: AppTheme.glassDecoration,
                                    padding: const EdgeInsets.all(24.0),
                                    child: EndpointDisplay(
                                      label: 'Tailscale',
                                      value: tailscaleEndpoint,
                                      badgeLabel: 'REMOTE',
                                    ),
                                  ),
                              ],
                            ),
                          )
                        else if (!_isRunning)
                          const SizedBox(
                            width: double.infinity,
                            child: Text(
                              'Remote access will require manual port forwarding without Tailscale.',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppTheme.textSecondary,
                                fontStyle: FontStyle.italic,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),

                        const SizedBox(height: 64),
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 32,
                          runSpacing: 12,
                          children: [
                            TextButton(
                              onPressed: () {
                                Navigator.pushReplacementNamed(context, '/');
                              },
                              child: const Text('BACK'),
                            ),
                            SizedBox(
                              height: 60,
                              width: 200,
                              child: ElevatedButton(
                                onPressed: () {
                                  Navigator.pushReplacementNamed(
                                      context, '/folder-selection');
                                },
                                child: const Text('NEXT STEP'),
                              ),
                            ),
                          ],
                        ),
                        if (!_isRunning && !_isChecking) ...[
                          const SizedBox(height: 32),
                          TextButton.icon(
                            onPressed: _checkTailscale,
                            icon: const Icon(Icons.refresh_rounded, size: 20),
                            label: const Text('RECHECK STATUS'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusMessage() {
    if (_isContainerized) {
      final advertisedTailscaleHost = _advertisedTailscaleHost;
      if (advertisedTailscaleHost != null) {
        return 'Tailscale access goes through the host machine at $advertisedTailscaleHost.';
      }
    }
    if (_isRunning) {
      return 'Tailscale is active. Your server is secured and accessible remotely.';
    }
    if (_isInstalled) {
      return 'Tailscale is installed but not currently running.';
    }
    if (_isContainerized) {
      return 'Ariami is running inside a container, so Tailscale cannot be detected here. If Tailscale runs on the host machine, use the host Tailscale address on this port.';
    }
    return 'Tailscale was not detected on this machine.';
  }
}
