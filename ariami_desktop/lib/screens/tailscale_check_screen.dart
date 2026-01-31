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
      // Try multiple common Tailscale paths (cross-platform)
      final possiblePaths = [
        '/opt/homebrew/bin/tailscale', // macOS Homebrew ARM
        '/usr/local/bin/tailscale', // macOS Homebrew Intel
        '/usr/bin/tailscale', // Linux
        '/usr/sbin/tailscale', // Linux (some distros)
        r'C:\Program Files\Tailscale\tailscale.exe', // Windows
        r'C:\Program Files (x86)\Tailscale\tailscale.exe', // Windows 32-bit
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
        // Try using 'which' on Unix-like systems
        if (!Platform.isWindows) {
          try {
            final whichResult = await Process.run('which', ['tailscale']);
            if (whichResult.exitCode == 0) {
              tailscalePath = whichResult.stdout.toString().trim();
            }
          } catch (e) {
            // Ignore and continue
          }
        }

        // Try using 'where' on Windows
        if (Platform.isWindows) {
          try {
            final whereResult = await Process.run('where', ['tailscale']);
            if (whereResult.exitCode == 0) {
              final path = whereResult.stdout.toString().trim();
              if (path.isNotEmpty) {
                tailscalePath = path.split('\n').first.trim();
              }
            }
          } catch (e) {
            // Ignore and continue
          }
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
                const SizedBox(
                  width: 60,
                  height: 60,
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    color: Colors.white,
                  ),
                )
              else
                Icon(
                  _isInstalled
                      ? Icons.check_circle_rounded
                      : Icons.warning_rounded,
                  size: 80,
                  color: Colors.white,
                ),
              const SizedBox(height: 32),
              Text(
                _isChecking
                    ? 'Checking Status'
                    : (_isInstalled
                        ? 'Tailscale is Installed'
                        : 'Tailscale Missing'),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _statusMessage.replaceAll(
                    'Tailscale is installed!\n\n', ''), // Clean up redundant text
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 48),
              if (!_isChecking) ...[
                OutlinedButton(
                  onPressed: _checkTailscale,
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
                    'Check Again',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 16),
                if (_isInstalled)
                  OutlinedButton(
                    onPressed: () {
                      Navigator.pushReplacementNamed(
                          context, '/folder-selection');
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
                      'Continue',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
