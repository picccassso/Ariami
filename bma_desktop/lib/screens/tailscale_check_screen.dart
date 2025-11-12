import 'package:flutter/material.dart';
import 'dart:io';

class TailscaleCheckScreen extends StatefulWidget {
  const TailscaleCheckScreen({super.key});

  @override
  State<TailscaleCheckScreen> createState() => _TailscaleCheckScreenState();
}

class _TailscaleCheckScreenState extends State<TailscaleCheckScreen> {
  bool _isChecking = true;
  bool _isInstalled = false;
  String _statusMessage = 'Checking Tailscale status...';

  @override
  void initState() {
    super.initState();
    _checkTailscale();
  }

  Future<void> _checkTailscale() async {
    setState(() {
      _isChecking = true;
      _statusMessage = 'Checking Tailscale installation...';
    });

    try {
      // Try multiple common Tailscale paths
      final possiblePaths = [
        '/opt/homebrew/bin/tailscale',
        '/usr/local/bin/tailscale',
        '/usr/bin/tailscale',
      ];

      String? tailscalePath;

      // Find which path exists
      for (final path in possiblePaths) {
        if (await File(path).exists()) {
          tailscalePath = path;
          break;
        }
      }

      if (tailscalePath == null) {
        // Try using 'which' as fallback
        final whichResult = await Process.run('which', ['tailscale']);
        if (whichResult.exitCode == 0) {
          tailscalePath = whichResult.stdout.toString().trim();
        }
      }

      if (tailscalePath != null && tailscalePath.isNotEmpty) {
        _isInstalled = true;
        _statusMessage = 'Tailscale is installed!\n\nPlease ensure Tailscale is running before continuing.';
      } else {
        _isInstalled = false;
        _statusMessage = 'Tailscale is not installed.\nPlease install Tailscale from tailscale.com';
      }
    } catch (e) {
      _statusMessage = 'Error checking Tailscale: $e';
    }

    setState(() {
      _isChecking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tailscale Setup'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isChecking)
                const CircularProgressIndicator()
              else
                Icon(
                  _isInstalled
                      ? Icons.check_circle
                      : Icons.warning,
                  size: 80,
                  color: _isInstalled
                      ? Colors.green
                      : Colors.orange,
                ),
              const SizedBox(height: 24),
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 48),
              if (!_isChecking) ...[
                ElevatedButton(
                  onPressed: _checkTailscale,
                  child: const Text('Check Again'),
                ),
                const SizedBox(height: 16),
                if (_isInstalled)
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pushReplacementNamed(context, '/folder-selection');
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 48,
                        vertical: 16,
                      ),
                    ),
                    child: const Text(
                      'Continue',
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
