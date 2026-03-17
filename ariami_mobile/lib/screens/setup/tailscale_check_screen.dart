import 'package:flutter/material.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import '../../services/mobile_tailscale_service.dart';

class TailscaleCheckScreen extends StatefulWidget {
  const TailscaleCheckScreen({super.key});

  @override
  State<TailscaleCheckScreen> createState() => _TailscaleCheckScreenState();
}

class _TailscaleCheckScreenState extends State<TailscaleCheckScreen> {
  final _tailscaleService = MobileTailscaleService();
  TailscaleStatus _status = TailscaleStatus.checking;

  @override
  void initState() {
    super.initState();
    _checkTailscale();
  }

  Future<void> _checkTailscale() async {
    setState(() {
      _status = TailscaleStatus.checking;
    });

    final status = await _tailscaleService.checkTailscaleStatus();

    setState(() {
      _status = status;
    });
  }

  Future<void> _openTailscaleStore() async {
    final url = _tailscaleService.getInstallUrl();
    if (url.isNotEmpty) {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect to Your Server'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Local network',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'If your phone is on the same Wi-Fi as your desktop, you can connect directly with no extra setup.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                          height: 1.4,
                        ),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Remote access',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'To use Ariami away from home, install and connect Tailscale on both your desktop and phone.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // Status Icon
                _buildStatusIcon(),
                const SizedBox(height: 32),

                // Status Title
                Text(
                  _getStatusTitle(),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // Status Description
                Text(
                  _getStatusDescription(),
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Instructions (if needed)
                if (_status != TailscaleStatus.connected &&
                    _status != TailscaleStatus.checking)
                  _buildInstructions(),

                const SizedBox(height: 32),

                // Action Buttons
                _buildActionButtons(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIcon() {
    switch (_status) {
      case TailscaleStatus.connected:
        return Icon(
          Icons.check_circle,
          size: 120,
          color: Colors.green[600],
        );
      case TailscaleStatus.notDetected:
        return Icon(
          Icons.info_outline_rounded,
          size: 120,
          color: Colors.blue[300],
        );
      case TailscaleStatus.installedNotConnected:
        return Icon(
          Icons.warning,
          size: 120,
          color: Colors.orange[600],
        );
      case TailscaleStatus.checking:
        return const SizedBox(
          width: 120,
          height: 120,
          child: CircularProgressIndicator(
            strokeWidth: 6,
          ),
        );
    }
  }

  String _getStatusTitle() {
    switch (_status) {
      case TailscaleStatus.connected:
        return 'Tailscale Ready';
      case TailscaleStatus.notDetected:
        return 'Tailscale Optional';
      case TailscaleStatus.installedNotConnected:
        return 'Tailscale Not Connected';
      case TailscaleStatus.checking:
        return 'Checking Remote Access...';
    }
  }

  String _getStatusDescription() {
    switch (_status) {
      case TailscaleStatus.connected:
        return 'Tailscale is active. Local setup will work, and remote access will be available too.';
      case TailscaleStatus.notDetected:
        return 'Tailscale was not detected. You can continue with local setup now, but you will need Tailscale later for remote access.';
      case TailscaleStatus.installedNotConnected:
        return 'Tailscale is installed but not connected. You can still continue with local setup, or connect Tailscale now for remote access.';
      case TailscaleStatus.checking:
        return 'Please wait while we check whether Tailscale is available for remote access.';
    }
  }

  Widget _buildInstructions() {
    final instructions = _tailscaleService.getSetupInstructions();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[900]!.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[700]!, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Remote Access Setup:',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.blue[100],
            ),
          ),
          const SizedBox(height: 12),
          ...instructions.map((instruction) => Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ',
                        style: TextStyle(fontSize: 16, color: Colors.white70)),
                    Expanded(
                      child: Text(
                        instruction,
                        style: const TextStyle(
                            fontSize: 14, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    if (_status == TailscaleStatus.checking) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        // Install/Open Tailscale button
        if (_status == TailscaleStatus.notDetected)
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _openTailscaleStore,
              icon: const Icon(Icons.download),
              label: Text(
                Platform.isAndroid ? 'Open Play Store' : 'Open App Store',
                style: const TextStyle(fontSize: 18),
              ),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

        // Check Again button
        SizedBox(
          width: double.infinity,
          height: 56,
          child: OutlinedButton.icon(
            onPressed: _checkTailscale,
            icon: const Icon(Icons.refresh),
            label: const Text(
              'Check Again',
              style: TextStyle(fontSize: 18),
            ),
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: () {
              Navigator.pushNamed(context, '/setup/scanner');
            },
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              _status == TailscaleStatus.connected
                  ? 'Continue to Scanner'
                  : 'Continue with Local Setup',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}
