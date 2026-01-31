import 'package:flutter/material.dart';
import '../services/web_tailscale_service.dart';
import '../utils/constants.dart';

class TailscaleCheckScreen extends StatefulWidget {
  const TailscaleCheckScreen({super.key});

  @override
  State<TailscaleCheckScreen> createState() => _TailscaleCheckScreenState();
}

class _TailscaleCheckScreenState extends State<TailscaleCheckScreen> with SingleTickerProviderStateMixin {
  final WebTailscaleService _tailscaleService = WebTailscaleService();

  bool _isChecking = true;
  bool _isInstalled = false;
  bool _isRunning = false;
  String? _tailscaleIp;

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

      if (mounted) {
        setState(() {
          _isChecking = false;
          _isInstalled = status['isInstalled'] as bool? ?? false;
          _isRunning = status['isRunning'] as bool? ?? false;
          _tailscaleIp = status['ip'] as String?;
        });
      }
    } catch (e) {
      if (mounted) {
         setState(() {
          _isChecking = false;
          _isInstalled = false;
          _isRunning = false;
          _tailscaleIp = null;
        });
      }
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
              title: const Text('SETUP'),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
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
                                ? Colors.white.withOpacity(0.05)
                                : (_isInstalled
                                    ? Colors.amberAccent.withOpacity(0.05)
                                    : Colors.redAccent.withOpacity(0.05)),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _isRunning
                                  ? Colors.white.withOpacity(0.1)
                                  : (_isInstalled
                                      ? Colors.amberAccent.withOpacity(0.1)
                                      : Colors.redAccent.withOpacity(0.1)),
                            ),
                          ),
                          child: Icon(
                            _isRunning
                                ? Icons.vpn_lock_rounded
                                : (_isInstalled ? Icons.info_rounded : Icons.info_outline_rounded),
                            size: 64,
                            color: _isRunning
                                ? Colors.white
                                : (_isInstalled ? Colors.amberAccent : Colors.redAccent),
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
                        width: 500,
                        child: Text(
                          _isRunning
                              ? 'Tailscale is active. Your server is secured and accessible remotely.'
                              : _isInstalled
                                  ? 'Tailscale is installed but not currently running.'
                                  : 'Tailscale was not detected on this machine.',
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
                      else if (_tailscaleIp != null)
                        Container(
                          width: 400,
                          decoration: AppTheme.glassDecoration,
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            children: [
                              const Text(
                                'SECURE MESH IP',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textSecondary,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _tailscaleIp!,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (!_isRunning)
                        const SizedBox(
                          width: 500,
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton(
                            onPressed: () {
                              Navigator.pushReplacementNamed(context, '/welcome');
                            },
                            child: const Text('BACK'),
                          ),
                          const SizedBox(width: 32),
                          SizedBox(
                            height: 60,
                            width: 200,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pushReplacementNamed(context, '/folder-selection');
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
          ],
        ),
      ),
    );
  }
}
