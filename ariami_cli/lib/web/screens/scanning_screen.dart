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
  int _skippedFileCount = 0;
  bool _isScanning = true;
  bool _isComplete = false;
  bool _isTransitioning = false;
  String? _transitionError;

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
        _skippedFileCount = status['skippedFileCount'] as int? ?? 0;
        _statusMessage = (status['currentStatus'] as String? ?? 'Scanning...').toUpperCase();
      });

      if (_isComplete || _isTransitioning) {
        return;
      }

      final scanFinished = !_isScanning && _progress >= 1.0;
      if (scanFinished) {
        _pollTimer?.cancel();
        await _handleScanComplete();
      }
    } catch (e) {
      debugPrint('Error updating scan status: $e');
    }
  }

  Future<void> _handleScanComplete() async {
    if (!mounted) return;

    setState(() {
      _isComplete = true;
      _isTransitioning = true;
      _transitionError = null;
      _statusMessage = 'MOVING SERVER TO BACKGROUND...';
    });

    final result = await _setupService.transitionToBackground();

    if (!mounted) return;

    final success = result['success'] as bool? ?? false;
    final message = result['message'] as String? ?? '';
    final expectedDisconnect = success || _isLikelyExpectedDisconnect(message);

    if (expectedDisconnect) {
      setState(() {
        _statusMessage = 'RECONNECTING...';
      });
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/owner-setup');
      }
      return;
    }

    setState(() {
      _isTransitioning = false;
      _transitionError = message.isNotEmpty
          ? message
          : 'Could not move the server to background mode.';
      _statusMessage = 'TRANSITION FAILED';
    });
  }

  Future<void> _retryBackgroundTransition() async {
    if (!mounted) return;

    setState(() {
      _isTransitioning = true;
      _transitionError = null;
      _statusMessage = 'MOVING SERVER TO BACKGROUND...';
    });

    final result = await _setupService.transitionToBackground();
    if (!mounted) return;

    final success = result['success'] as bool? ?? false;
    final message = result['message'] as String? ?? '';
    final expectedDisconnect = success || _isLikelyExpectedDisconnect(message);

    if (expectedDisconnect) {
      setState(() {
        _statusMessage = 'RECONNECTING...';
      });
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/owner-setup');
      }
      return;
    }

    setState(() {
      _isTransitioning = false;
      _transitionError = message.isNotEmpty
          ? message
          : 'Could not move the server to background mode.';
      _statusMessage = 'TRANSITION FAILED';
    });
  }

  void _continueInForeground() {
    Navigator.pushReplacementNamed(context, '/owner-setup');
  }

  bool _isLikelyExpectedDisconnect(String message) {
    final lower = message.toLowerCase();
    return lower.contains('connection closed') ||
        lower.contains('connection reset') ||
        lower.contains('connection refused') ||
        lower.contains('socketexception') ||
        lower.contains('clientexception') ||
        lower.contains('failed to fetch') ||
        lower.contains('network is unreachable');
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
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
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
                        width: double.infinity,
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
                        width: double.infinity,
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
                      if (_isComplete && _skippedFileCount > 0) ...[
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.amber.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  color: Colors.amber.shade300,
                                  size: 22,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '$_skippedFileCount FILE(S) COULD NOT BE READ AND WERE SKIPPED',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.amber.shade100,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (_isComplete && _isTransitioning) ...[
                        const SizedBox(height: 64),
                        SizedBox(
                          width: double.infinity,
                          child: Column(
                            children: [
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
                                  Text(
                                    _statusMessage,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.textSecondary,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'The page may disconnect briefly while the server moves to background mode.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textSecondary,
                                  height: 1.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Refresh if it does not reconnect automatically.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textSecondary,
                                  height: 1.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_transitionError != null) ...[
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.redAccent.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  _transitionError!,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.white,
                                    height: 1.5,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 20),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 16,
                                  runSpacing: 12,
                                  children: [
                                    OutlinedButton(
                                      onPressed: _retryBackgroundTransition,
                                      child: const Text('RETRY'),
                                    ),
                                    ElevatedButton(
                                      onPressed: _continueInForeground,
                                      child: const Text('CONTINUE IN FOREGROUND'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
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
