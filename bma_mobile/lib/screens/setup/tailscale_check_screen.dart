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
        title: const Text('Tailscale Setup'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
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
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[700],
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
          Icons.error,
          size: 120,
          color: Colors.red[600],
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
        return 'Connected to Tailscale';
      case TailscaleStatus.notDetected:
        return 'Tailscale Not Detected';
      case TailscaleStatus.installedNotConnected:
        return 'Tailscale Not Connected';
      case TailscaleStatus.checking:
        return 'Checking Tailscale Status...';
    }
  }

  String _getStatusDescription() {
    switch (_status) {
      case TailscaleStatus.connected:
        return 'Your device is connected to the Tailscale network. You can now scan the QR code from your desktop.';
      case TailscaleStatus.notDetected:
        return 'Tailscale is required to securely connect to your desktop music server.';
      case TailscaleStatus.installedNotConnected:
        return 'Tailscale is installed but not connected. Please open Tailscale and connect to your network.';
      case TailscaleStatus.checking:
        return 'Please wait while we check your Tailscale connection...';
    }
  }

  Widget _buildInstructions() {
    final instructions = _tailscaleService.getSetupInstructions();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Setup Instructions:',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...instructions.map((instruction) => Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(fontSize: 16)),
                    Expanded(
                      child: Text(
                        instruction,
                        style: const TextStyle(fontSize: 14),
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

        // Continue button (only when connected)
        if (_status == TailscaleStatus.connected)
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () {
                // TODO: Navigate to QR scanner
                Navigator.pushNamed(context, '/setup/scanner');
              },
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Continue',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
          ),
      ],
    );
  }
}
