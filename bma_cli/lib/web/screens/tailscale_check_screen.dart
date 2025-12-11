import 'package:flutter/material.dart';
import '../services/web_tailscale_service.dart';

class TailscaleCheckScreen extends StatefulWidget {
  const TailscaleCheckScreen({super.key});

  @override
  State<TailscaleCheckScreen> createState() => _TailscaleCheckScreenState();
}

class _TailscaleCheckScreenState extends State<TailscaleCheckScreen> {
  final WebTailscaleService _tailscaleService = WebTailscaleService();

  bool _isChecking = true;
  bool _isInstalled = false;
  bool _isRunning = false;
  String? _tailscaleIp;

  @override
  void initState() {
    super.initState();
    _checkTailscale();
  }

  Future<void> _checkTailscale() async {
    setState(() => _isChecking = true);

    try {
      final status = await _tailscaleService.checkTailscaleStatus();

      setState(() {
        _isChecking = false;
        _isInstalled = status['isInstalled'] as bool? ?? false;
        _isRunning = status['isRunning'] as bool? ?? false;
        _tailscaleIp = status['ip'] as String?;
      });
    } catch (e) {
      setState(() {
        _isChecking = false;
        _isInstalled = false;
        _isRunning = false;
        _tailscaleIp = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tailscale Setup'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isChecking)
                const Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 24),
                    Text('Checking Tailscale installation...'),
                  ],
                )
              else ...[
                Icon(
                  _isRunning ? Icons.check_circle : (_isInstalled ? Icons.info : Icons.info),
                  size: 80,
                  color: _isRunning ? Colors.green : Colors.orange,
                ),
                const SizedBox(height: 24),
                Text(
                  _isRunning
                      ? 'Tailscale is installed and running'
                      : _isInstalled
                          ? 'Tailscale is installed but not running'
                          : 'Tailscale not detected',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_tailscaleIp != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'IP Address: $_tailscaleIp',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                ],
                if (!_isRunning) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Tailscale enables secure remote access to your music server.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'You can install it later or continue without it.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 48),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.pushReplacementNamed(context, '/');
                      },
                      child: const Text('Back'),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pushReplacementNamed(
                            context, '/folder-selection');
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                      ),
                      child: const Text(
                        'Continue',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
