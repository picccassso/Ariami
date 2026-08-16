import 'package:flutter/material.dart';
import '../services/web_tailscale_service.dart';
import '../onboarding/setup_help.dart';
import '../widgets/endpoint_display.dart';
import '../widgets/ui/section.dart';
import '../widgets/ui/setup_scaffold.dart';
import '../widgets/ui/status_pill.dart';

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
    final hasEndpoints = lanEndpoint != null || tailscaleEndpoint != null;

    return SetupScaffold(
      step: 1,
      icon: Icons.vpn_lock_rounded,
      title: 'Remote access',
      description: _statusMessage(),
      helpTopic: CliOnboardingCopy.tailscale,
      secondaryAction: TextButton(
        onPressed: () {
          Navigator.pushReplacementNamed(context, '/');
        },
        child: const Text('Back'),
      ),
      primaryAction: ElevatedButton.icon(
        onPressed: () {
          Navigator.pushReplacementNamed(context, '/folder-selection');
        },
        icon: const Icon(Icons.arrow_forward_rounded, size: 19),
        iconAlignment: IconAlignment.end,
        label: const Text('Continue'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: StatusPill(
              label: _isChecking
                  ? 'Checking Tailscale'
                  : _isRunning
                      ? 'Tailscale active'
                      : _isInstalled
                          ? 'Tailscale installed, not running'
                          : 'Tailscale not detected',
              tone: _isRunning
                  ? StatusTone.positive
                  : _isInstalled
                      ? StatusTone.caution
                      : StatusTone.neutral,
              busy: _isChecking,
              pulse: _isRunning ? _pulseController : null,
            ),
          ),
          if (hasEndpoints) ...[
            const SizedBox(height: 20),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  if (lanEndpoint != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: EndpointDisplay(
                        label: 'Local network',
                        value: lanEndpoint,
                        badgeLabel: 'LAN',
                      ),
                    ),
                  if (lanEndpoint != null && tailscaleEndpoint != null)
                    const CardDivider(),
                  if (tailscaleEndpoint != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: EndpointDisplay(
                        label: 'Tailscale',
                        value: tailscaleEndpoint,
                        badgeLabel: 'REMOTE',
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (!_isRunning && !_isChecking) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _checkTailscale,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Check again'),
              ),
            ),
          ],
        ],
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
      return 'Tailscale is active. Devices signed in to the same Tailscale account can reach Ariami remotely.';
    }
    if (_isInstalled) {
      return 'Tailscale is installed but not currently running.';
    }
    if (_isContainerized) {
      return 'Ariami is running inside a container, so Tailscale cannot be detected here. If Tailscale runs on the host machine, use the host Tailscale address on this port.';
    }
    return 'Tailscale was not detected. You can continue with local-network setup and add it later.';
  }
}
