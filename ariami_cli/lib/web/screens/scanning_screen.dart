import 'dart:async';
import 'package:flutter/material.dart';
import '../services/web_setup_service.dart';
import '../utils/constants.dart';

class ScanningScreen extends StatefulWidget {
  const ScanningScreen({super.key});

  @override
  State<ScanningScreen> createState() => _ScanningScreenState();
}

class _ScanningScreenState extends State<ScanningScreen> with SingleTickerProviderStateMixin {
  final WebSetupService _setupService = WebSetupService();

  double _progress = 0.0;
  String _statusMessage = 'INITIALIZING SCAN...';
  int _songsFound = 0;
  int _albumsFound = 0;
  bool _isScanning = true;
  bool _isComplete = false;

  Timer? _pollTimer;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _startScanning();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startScanning() async {
    try {
      final success = await _setupService.startScan();

      if (!success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to start scan'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
            ),
          );
          Navigator.pushReplacementNamed(context, '/folder-selection');
        }
        return;
      }

      _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        _updateScanStatus();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting scan: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pushReplacementNamed(context, '/folder-selection');
      }
    }
  }

  Future<void> _updateScanStatus() async {
    try {
      final status = await _setupService.getScanStatus();

      if (!mounted) return;

      setState(() {
        _isScanning = status['isScanning'] as bool? ?? false;
        _progress = (status['progress'] as num?)?.toDouble() ?? 0.0;
        _songsFound = status['songsFound'] as int? ?? 0;
        _albumsFound = status['albumsFound'] as int? ?? 0;
        _statusMessage = (status['currentStatus'] as String? ?? 'Scanning...').toUpperCase();
        _isComplete = !_isScanning && _progress >= 1.0;
      });

      if (_isComplete) {
        _pollTimer?.cancel();
        await _setupService.markSetupComplete();
        await _setupService.transitionToBackground();

        await Future.delayed(const Duration(seconds: 3));
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/qr-code');
        }
      }
    } catch (e) {
      debugPrint('Error updating scan status: $e');
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
              title: const Text('INDEXING'),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Pulse Icon
                      FadeTransition(
                        opacity: _pulseController,
                        child: Container(
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: Icon(
                            _isComplete ? Icons.check_rounded : Icons.search_rounded,
                            size: 64,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 48),
                      Text(
                        _isComplete ? 'SCAN COMPLETE' : 'BUILDING LIBRARY',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _statusMessage,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textSecondary,
                          letterSpacing: 2.0,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 64),

                      // Progress Bar Container
                      SizedBox(
                        width: 600,
                        child: Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: LinearProgressIndicator(
                                value: _progress,
                                minHeight: 12,
                                backgroundColor: Colors.white.withOpacity(0.05),
                                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${(_progress * 100).toInt()}% COMPLETE',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                                if (!_isComplete)
                                  const Text(
                                    'STAY ON THIS PAGE',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 64),

                      // Stats Grid
                      SizedBox(
                        width: 600,
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildCountCard(
                                icon: Icons.audiotrack_rounded,
                                count: '$_songsFound',
                                label: 'SONGS FOUND',
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: _buildCountCard(
                                icon: Icons.album_rounded,
                                count: '$_albumsFound',
                                label: 'ALBUMS INDEXED',
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_isComplete) ...[
                        const SizedBox(height: 64),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(width: 16),
                            const Text(
                              'REDIRECTING...',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textSecondary,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
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

  Widget _buildCountCard({
    required IconData icon,
    required String count,
    required String label,
  }) {
    return Container(
      decoration: AppTheme.glassDecoration,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        children: [
          Icon(icon, size: 24, color: AppTheme.textSecondary),
          const SizedBox(height: 16),
          Text(
            count,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: AppTheme.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
