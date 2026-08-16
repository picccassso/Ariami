import 'dart:async';
import 'package:flutter/material.dart';
import '../services/web_setup_service.dart';
import '../onboarding/setup_help.dart';
import '../utils/constants.dart';
import '../widgets/ui/setup_scaffold.dart';
import '../widgets/ui/status_pill.dart';

class ScanningScreen extends StatefulWidget {
  const ScanningScreen({super.key});

  @override
  State<ScanningScreen> createState() => _ScanningScreenState();
}

class _ScanningScreenState extends State<ScanningScreen>
    with SingleTickerProviderStateMixin {
  final WebSetupService _setupService = WebSetupService();

  double _progress = 0.0;
  String _statusMessage = 'Starting scan…';
  int _songsFound = 0;
  int _albumsFound = 0;
  int _scannedFileCount = 0;
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
              backgroundColor: AppTheme.danger,
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
            backgroundColor: AppTheme.danger,
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
        _scannedFileCount = status['scannedFileCount'] as int? ?? 0;
        _skippedFileCount = status['skippedFileCount'] as int? ?? 0;
        _statusMessage =
            (status['currentStatus'] as String? ?? 'Scanning...').toUpperCase();
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
      _isTransitioning = false;
      _transitionError = null;
      _statusMessage = 'SCAN COMPLETE!';
    });
  }

  Future<void> _transitionToBackground() async {
    if (!mounted || _isTransitioning) return;

    setState(() {
      _isTransitioning = true;
      _transitionError = null;
      _statusMessage = 'Moving the server to background mode…';
    });

    final result = await _setupService.transitionToBackground();

    if (!mounted) return;

    final success = result['success'] as bool? ?? false;
    final alreadyInForeground = result['alreadyInForeground'] as bool? ?? false;
    final message = result['message'] as String? ?? '';
    final expectedDisconnect = success || _isLikelyExpectedDisconnect(message);

    if (expectedDisconnect) {
      setState(() {
        _statusMessage =
            alreadyInForeground ? 'Finishing setup…' : 'Reconnecting…';
      });
      await Future.delayed(
        alreadyInForeground
            ? const Duration(milliseconds: 500)
            : const Duration(seconds: 3),
      );
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
      _statusMessage = 'Could not move to background mode';
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
    return SetupScaffold(
      step: 3,
      icon: _isComplete ? Icons.check_rounded : Icons.search_rounded,
      title: _isComplete ? 'Library ready' : 'Building your library',
      description: _isComplete
          ? 'Ariami read the tags and artwork in your music folder and grouped '
              'everything into albums and artists.'
          : 'Ariami is reading the tags and artwork in your music folder. '
              'Keep this page open until it finishes.',
      helpTopic: CliOnboardingCopy.scanning,
      primaryAction: _isComplete && !_isTransitioning && _transitionError == null
          ? ElevatedButton.icon(
              onPressed: _transitionToBackground,
              icon: const Icon(Icons.arrow_forward_rounded, size: 19),
              iconAlignment: IconAlignment.end,
              label: const Text('Continue'),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 6,
              backgroundColor: AppTheme.surfaceRaised,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${(_progress * 100).toInt()}%',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              Flexible(
                child: Text(
                  _statusMessage,
                  style: AppTheme.meta,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _buildCountCard(
                  icon: Icons.audiotrack_rounded,
                  count: '$_songsFound',
                  label: 'Songs',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCountCard(
                  icon: Icons.album_rounded,
                  count: '$_albumsFound',
                  label: 'Albums',
                ),
              ),
              if (_isComplete) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _buildCountCard(
                    icon: Icons.folder_open_rounded,
                    count: '$_scannedFileCount',
                    label: 'Files scanned',
                  ),
                ),
              ],
            ],
          ),
          if (_isComplete && _skippedFileCount > 0) ...[
            const SizedBox(height: 16),
            NoticeBanner(
              icon: Icons.warning_amber_rounded,
              tone: StatusTone.caution,
              message: '$_skippedFileCount file(s) were skipped. This is '
                  'usually informational; the rest of your library is '
                  'unaffected.',
            ),
          ],
          if (_isComplete && _isTransitioning) ...[
            const SizedBox(height: 20),
            const NoticeBanner(
              icon: Icons.sync_rounded,
              tone: StatusTone.neutral,
              message: 'Moving the server to background mode. This page may '
                  'disconnect briefly — refresh if it does not come back on '
                  'its own.',
            ),
          ],
          if (_transitionError != null) ...[
            const SizedBox(height: 20),
            NoticeBanner(
              icon: Icons.error_outline_rounded,
              tone: StatusTone.negative,
              message: _transitionError!,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton(
                  onPressed: _transitionToBackground,
                  child: const Text('Try again'),
                ),
                ElevatedButton(
                  onPressed: _continueInForeground,
                  child: const Text('Continue in foreground'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCountCard({
    required IconData icon,
    required String count,
    required String label,
  }) {
    return Container(
      decoration: AppTheme.cardDecoration(),
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppTheme.textSecondary),
          const SizedBox(height: 12),
          Text(
            count,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
              letterSpacing: -1,
              height: 1.15,
            ),
          ),
          Text(label, style: AppTheme.fieldLabel),
        ],
      ),
    );
  }
}
